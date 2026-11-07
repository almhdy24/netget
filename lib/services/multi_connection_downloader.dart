import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/segment_planner.dart';
import '../models/download_status.dart';

const String _defaultUserAgent = 'NetGet/1.0 (Android; en-US)';

/// Thread-safe concurrent file writer ensuring serialized, non-overlapping writes.
class ConcurrentFileWriter {
  final RandomAccessFile _raf;
  Future<void> _writeQueue = Future.value();
  bool _isClosed = false;

  ConcurrentFileWriter(this._raf);

  /// Pre-allocates file size to minimize disk fragmentation and prepare for random writes.
  Future<void> preallocate(int totalBytes) async {
    if (totalBytes > 0) {
      try {
        await _raf.truncate(totalBytes);
      } catch (_) {}
    }
  }

  /// Atomically seeks to [offset] and writes [bytes] without concurrency races.
  Future<void> writeAt(int offset, List<int> bytes) {
    if (_isClosed) return Future.value();
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      if (_isClosed) {
        completer.complete();
        return;
      }
      try {
        await _raf.setPosition(offset);
        await _raf.writeFrom(bytes);
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> flush() async {
    if (_isClosed) return;
    await _writeQueue;
    try {
      await _raf.flush();
    } catch (_) {}
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _writeQueue;
    try {
      await _raf.close();
    } catch (_) {}
  }
}

/// Result metadata returned after link probe.
class LinkProbeResult {
  final bool isRangeSupported;
  final int totalBytes;
  final String? etag;
  final String? lastModified;
  final String? suggestedFileName;

  LinkProbeResult({
    required this.isRangeSupported,
    required this.totalBytes,
    this.etag,
    this.lastModified,
    this.suggestedFileName,
  });
}

/// Real Multi-Connection Parallel Range Download Engine.
class MultiConnectionDownloader {
  final String id;
  final Uri uri;
  final String savePath;
  final int connectionCount;
  final HttpClient Function() clientFactory;
  final void Function(int downloadedBytes, int totalBytes, double speedBytesPerSec, List<DownloadSegment> segments)? onProgress;
  final void Function(String level, String message)? onLog;

  bool _isPaused = false;
  bool _isCancelled = false;
  ConcurrentFileWriter? _writer;
  final List<HttpClient> _activeClients = [];
  final List<HttpClientRequest> _activeRequests = [];

  List<DownloadSegment> segments = [];
  int totalBytes = -1;
  String? etag;
  String? lastModified;
  bool isRangeSupported = false;

  MultiConnectionDownloader({
    required this.id,
    required this.uri,
    required this.savePath,
    this.connectionCount = 4,
    required this.clientFactory,
    this.onProgress,
    this.onLog,
    this.etag,
    this.lastModified,
    List<DownloadSegment>? initialSegments,
  }) {
    if (initialSegments != null && initialSegments.isNotEmpty) {
      segments = List.from(initialSegments);
    }
  }

  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  void _log(String level, String msg) {
    onLog?.call(level, msg);
  }

  /// Probes server headers to determine range support, content length, and ETags.
  Future<LinkProbeResult> probeServer() async {
    final client = clientFactory();
    _activeClients.add(client);
    try {
      final request = await client.openUrl('GET', uri);
      _activeRequests.add(request);
      request.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');

      final response = await request.close();
      final statusCode = response.statusCode;

      if (_isPaused || _isCancelled) {
        return LinkProbeResult(isRangeSupported: false, totalBytes: -1);
      }

      if (statusCode >= 400 && statusCode != HttpStatus.requestedRangeNotSatisfiable) {
        throw HttpException('Server returned HTTP $statusCode', uri: uri);
      }

      final hasRange = (statusCode == HttpStatus.partialContent);
      int length = -1;

      if (hasRange) {
        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null && contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          length = int.tryParse(totalStr) ?? -1;
        }
      } else {
        length = response.contentLength;
      }

      final serverEtag = response.headers.value(HttpHeaders.etagHeader);
      final serverLastModified = response.headers.value(HttpHeaders.lastModifiedHeader);

      // Drain probe response body
      await response.drain<void>();

      return LinkProbeResult(
        isRangeSupported: hasRange,
        totalBytes: length,
        etag: serverEtag,
        lastModified: serverLastModified,
      );
    } catch (e) {
      if (_isPaused || _isCancelled) {
        return LinkProbeResult(isRangeSupported: false, totalBytes: -1);
      }
      rethrow;
    } finally {
      client.close(force: true);
      _activeClients.remove(client);
    }
  }

  /// Starts or resumes multi-connection downloading.
  Future<void> start() async {
    _isPaused = false;
    _isCancelled = false;

    final file = File(savePath);
    await file.parent.create(recursive: true);

    // Step 1: Probe server if capabilities/size not known
    if (totalBytes <= 0 || !isRangeSupported) {
      _log('INFO', 'Probing server capabilities...');
      final probe = await probeServer();
      if (_isPaused || _isCancelled) return;

      if (etag != null && probe.etag != null && probe.etag != etag) {
        throw HttpException(
          'Server file changed (ETag mismatch: ${probe.etag} vs $etag)',
          uri: uri,
        );
      }

      isRangeSupported = probe.isRangeSupported;
      totalBytes = probe.totalBytes;
      etag = probe.etag ?? etag;
      lastModified = probe.lastModified ?? lastModified;
      _log(
        'INFO',
        'Server Range: ${isRangeSupported ? "Supported" : "Unsupported"}, Size: $totalBytes',
      );
    }

    if (_isPaused || _isCancelled) return;

    // Step 2: Open file and preallocate
    final raf = await file.open(mode: FileMode.append);
    _writer = ConcurrentFileWriter(raf);
    if (totalBytes > 0) {
      await _writer!.preallocate(totalBytes);
    }

    // Step 3: Segment Planning
    final effectiveConnections = (isRangeSupported && totalBytes > 256 * 1024)
        ? connectionCount.clamp(1, 16)
        : 1;

    if (segments.isEmpty) {
      segments = SegmentPlanner.planInitialSegments(
        totalBytes: totalBytes,
        connectionCount: effectiveConnections,
        resumable: isRangeSupported,
      );
    }

    _log('INFO', 'Launching download with ${segments.length} segment(s)');

    // Step 4: Launch worker tasks
    final stopwatch = Stopwatch()..start();
    var lastEmitTime = DateTime.now();
    var bytesSinceTick = 0;

    void notifyProgressTick(int chunkBytes) {
      bytesSinceTick += chunkBytes;
      final now = DateTime.now();
      final diff = now.difference(lastEmitTime).inMilliseconds;
      if (diff >= 500) {
        final sec = stopwatch.elapsedMicroseconds / 1000000.0;
        final speed = sec > 0 ? (bytesSinceTick / sec) : 0.0;
        stopwatch.reset();
        bytesSinceTick = 0;
        lastEmitTime = now;

        final totalDownloaded = segments.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
        onProgress?.call(totalDownloaded, totalBytes, speed, segments);
      }
    }

    final workerFutures = <Future<void>>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (!seg.isFinished) {
        workerFutures.add(_runSegmentWorker(seg, notifyProgressTick));
      }
    }

    try {
      await Future.wait(workerFutures);
      await _writer?.flush();
    } finally {
      await _writer?.close();
    }

    if (!_isPaused && !_isCancelled) {
      final totalDownloaded = segments.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
      onProgress?.call(totalDownloaded, totalBytes, 0.0, segments);
      _log('INFO', 'All segments completed successfully.');
    }
  }

  /// Worker task downloading a single byte-range segment.
  Future<void> _runSegmentWorker(
    DownloadSegment segment,
    void Function(int chunkLength) onChunk,
  ) async {
    while (!segment.isFinished && !_isPaused && !_isCancelled) {
      final client = clientFactory();
      _activeClients.add(client);

      try {
        final request = await client.openUrl('GET', uri);
        _activeRequests.add(request);
        request.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

        final startOffset = segment.currentOffset;
        final endOffset = segment.endByte;

        if (isRangeSupported && endOffset >= startOffset) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-$endOffset');
          if (etag != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, etag!);
          } else if (lastModified != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, lastModified!);
          }
        }

        final response = await request.close();
        final statusCode = response.statusCode;

        // Check for ETag validation across connections
        final respEtag = response.headers.value(HttpHeaders.etagHeader);
        if (etag != null && respEtag != null && respEtag != etag) {
          throw HttpException('Server file changed (ETag mismatch: $respEtag vs $etag)', uri: uri);
        }

        if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          // Range 416: segment is already complete or out of bounds
          segment.isCompleted = true;
          return;
        }

        if (statusCode != HttpStatus.partialContent && statusCode != HttpStatus.ok) {
          throw HttpException('HTTP $statusCode: ${response.reasonPhrase}', uri: uri);
        }

        await for (final chunk in response) {
          if (_isPaused || _isCancelled) {
            break;
          }

          // Write chunk at current offset
          final writeOffset = segment.currentOffset;
          await _writer?.writeAt(writeOffset, chunk);

          segment.downloadedBytes += chunk.length;
          onChunk(chunk.length);

          if (segment.isFinished) {
            break;
          }
        }

        if (segment.remainingBytes <= 0 && segment.endByte >= 0) {
          segment.isCompleted = true;
        } else if (!_isPaused && !_isCancelled) {
          throw HttpException(
            'Incomplete segment transfer: ${segment.remainingBytes} bytes remaining',
            uri: uri,
          );
        }

        // Dynamic Segment Re-splitting:
        // If this worker finished its segment, look for an active segment with >= 512 KB left to split!
        if (segment.isCompleted && !_isPaused && !_isCancelled) {
          final newSegment = SegmentPlanner.splitLargestSegment(segments, minThreshold: 512 * 1024);
          if (newSegment != null) {
            _log('INFO', 'Segment ${segment.index} re-split segment ${newSegment.index} [${newSegment.startByte}..${newSegment.endByte}]');
            await _runSegmentWorker(newSegment, onChunk);
          }
        }
      } catch (e) {
        if (_isPaused || _isCancelled) return;
        rethrow;
      } finally {
        client.close(force: true);
        _activeClients.remove(client);
      }
    }
  }

  /// Gracefully pauses transfer, aborting in-flight sockets and flushing file writes.
  Future<void> pause() async {
    _isPaused = true;
    for (final req in _activeRequests) {
      try {
        req.abort();
      } catch (_) {}
    }
    for (final client in _activeClients) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    await _writer?.flush();
    await _writer?.close();
    _log('INFO', 'Download paused');
  }

  /// Cancels transfer and closes all resources.
  Future<void> cancel() async {
    _isCancelled = true;
    for (final req in _activeRequests) {
      try {
        req.abort();
      } catch (_) {}
    }
    for (final client in _activeClients) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    await _writer?.close();
    _log('INFO', 'Download cancelled');
  }
}
