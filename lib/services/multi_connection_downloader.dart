import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/segment_planner.dart';
import '../core/utils.dart';

const String _defaultUserAgent = 'NetGet/1.0 (Android; en-US)';

/// Global pool that restricts concurrent HTTP connections per host across all active downloads.
/// The default limit of 6 connections per host follows the standard modern browser convention
/// (RFC 2616 § 8.1.4 historically recommended 2 connections per host).
class HostConnectionPool {
  static final HostConnectionPool defaultPool = HostConnectionPool();

  final int maxConnectionsPerHost;
  final Map<String, int> _activePerHost = {};

  HostConnectionPool({this.maxConnectionsPerHost = 6});

  /// Active connections currently open to [host].
  int activeCount(String host) => _activePerHost[host] ?? 0;

  /// Returns remaining available connection slots for [host].
  int availableSlots(String host) {
    final active = activeCount(host);
    final remaining = maxConnectionsPerHost - active;
    return remaining > 0 ? remaining : 0;
  }

  /// Acquires a connection slot for [host].
  /// Returns a release callback to be invoked when the connection closes.
  void Function() acquire(String host) {
    _activePerHost[host] = activeCount(host) + 1;
    bool released = false;
    return () {
      if (!released) {
        released = true;
        final current = _activePerHost[host] ?? 1;
        if (current <= 1) {
          _activePerHost.remove(host);
        } else {
          _activePerHost[host] = current - 1;
        }
      }
    };
  }

  /// Clamps requested connections to available slots for [host].
  int clampConnections(String host, int requested) {
    final available = availableSlots(host);
    return requested.clamp(1, max(1, min(available, maxConnectionsPerHost)));
  }

  void reset() {
    _activePerHost.clear();
  }
}

/// Thread-safe concurrent file writer ensuring serialized, non-overlapping writes.
class ConcurrentFileWriter {
  final RandomAccessFile _raf;
  Future<void> _writeQueue = Future.value();
  bool _isClosed = false;
  int flushCount = 0;
  int writeCount = 0;

  ConcurrentFileWriter(this._raf);

  /// Extends file size to [totalBytes] (sparse file on POSIX) to prepare for random-access writes.
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
        writeCount++;
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> flush() {
    if (_isClosed) return Future.value();
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      if (_isClosed) {
        completer.complete();
        return;
      }
      try {
        await _raf.flush();
        flushCount++;
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> close() {
    if (_isClosed) return Future.value();
    _isClosed = true;
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _raf.close();
      } catch (_) {}
      completer.complete();
    });
    return completer.future;
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

typedef DiskSpaceChecker = Future<int> Function(String directoryPath);

Future<int> defaultDiskSpaceChecker(String directoryPath) async {
  try {
    final result = await Process.run('df', ['-Pk', directoryPath]);
    if (result.exitCode == 0) {
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final availKb = int.tryParse(parts[3]);
          if (availKb != null) {
            return availKb * 1024;
          }
        }
      }
    }
  } catch (_) {}
  return -1;
}

/// Real Multi-Connection Parallel Range Download Engine.
class MultiConnectionDownloader {
  final String id;
  final Uri uri;
  final String savePath;
  final int connectionCount;
  final int maxConnectionsPerHost;
  final HostConnectionPool hostPool;
  final HttpClient Function() clientFactory;
  final void Function(int downloadedBytes, int totalBytes, double speedBytesPerSec, List<DownloadSegment> segments)? onProgress;
  final Future<void> Function(List<DownloadSegment> segments)? onCheckpoint;
  final void Function(String level, String message)? onLog;
  final DiskSpaceChecker? diskSpaceChecker;
  final Future<ConcurrentFileWriter> Function(File file)? writerFactory;

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
    this.maxConnectionsPerHost = 6,
    HostConnectionPool? hostPool,
    required this.clientFactory,
    this.onProgress,
    this.onCheckpoint,
    this.onLog,
    this.etag,
    this.lastModified,
    this.diskSpaceChecker,
    this.writerFactory,
    List<DownloadSegment>? initialSegments,
  }) : hostPool = hostPool ?? HostConnectionPool.defaultPool {
    if (initialSegments != null && initialSegments.isNotEmpty) {
      segments = List.from(initialSegments);
    }
  }

  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;
  ConcurrentFileWriter? get writer => _writer;

  /// Flushes in-flight bytes to disk and triggers an immutable checkpoint.
  Future<List<DownloadSegment>> checkpoint() async {
    await _writer?.flush();
    final snapshot = segments.map((s) => s.copyWith()).toList();
    if (onCheckpoint != null) {
      await onCheckpoint!(snapshot);
    }
    return snapshot;
  }

  void _log(String level, String msg) {
    onLog?.call(level, msg);
  }

  Duration calculateRetryDelayForTesting(int statusCode, String? retryAfterHeader, int attempt) {
    return _calculateRetryDelay(statusCode, retryAfterHeader, attempt);
  }

  Duration _calculateRetryDelay(int statusCode, String? retryAfterHeader, int attempt) {
    if (retryAfterHeader != null) {
      final seconds = int.tryParse(retryAfterHeader);
      if (seconds != null) {
        return Duration(seconds: seconds.clamp(0, 60));
      }
      try {
        final date = HttpDate.parse(retryAfterHeader);
        final diff = date.difference(DateTime.now());
        if (!diff.isNegative) {
          return diff > const Duration(seconds: 60) ? const Duration(seconds: 60) : diff;
        }
      } catch (_) {}
    }
    // Exponential backoff: 300ms, 600ms, 1200ms... capped at 10s (strictly <= 60s)
    final ms = (300 * pow(2, attempt)).toInt().clamp(100, 10000);
    return Duration(milliseconds: ms);
  }

  /// Probes server headers to determine range support, content length, and ETags.
  Future<LinkProbeResult> probeServer({int maxRetries = 3}) async {
    int attempt = 0;
    while (!_isPaused && !_isCancelled) {
      final client = clientFactory();
      _activeClients.add(client);
      final releaseHostSlot = hostPool.acquire(uri.host);
      try {
        final request = await client.openUrl('GET', uri);
        _activeRequests.add(request);
        request.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        if (NetGetUtils.isStrongEtag(etag)) {
          request.headers.set(HttpHeaders.ifRangeHeader, etag!);
        } else if (lastModified != null && lastModified!.trim().isNotEmpty) {
          request.headers.set(HttpHeaders.ifRangeHeader, lastModified!);
        }

        final response = await request.close();
        final statusCode = response.statusCode;

        if (_isPaused || _isCancelled) {
          await response.drain<void>();
          return LinkProbeResult(isRangeSupported: false, totalBytes: -1);
        }

        if (statusCode == HttpStatus.tooManyRequests || statusCode == HttpStatus.serviceUnavailable) {
          if (attempt >= maxRetries) {
            throw HttpException('Server returned HTTP $statusCode after $maxRetries retries', uri: uri);
          }
          final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
          final delay = _calculateRetryDelay(statusCode, retryAfter, attempt);
          _log('WARN', 'Probe returned HTTP $statusCode. Retrying in ${delay.inMilliseconds}ms (attempt ${attempt + 1}/$maxRetries)...');
          await response.drain<void>();
          attempt++;
          await Future.delayed(delay);
          continue;
        }

        if (statusCode >= 400) {
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
        releaseHostSlot();
        client.close(force: true);
        _activeClients.remove(client);
      }
    }
    return LinkProbeResult(isRangeSupported: false, totalBytes: -1);
  }

  /// Starts or resumes multi-connection downloading.
  Future<void> start() async {
    _isPaused = false;
    _isCancelled = false;

    final file = File(savePath);
    await file.parent.create(recursive: true);

    Timer? checkpointTimer;
    try {
      // Step 1: Probe server if capabilities/size not known
      if (totalBytes <= 0 || !isRangeSupported) {
        _log('INFO', 'Probing server capabilities...');
        final probe = await probeServer();
        if (_isPaused || _isCancelled) return;

        if (etag != null && probe.etag != null && probe.etag != etag) {
          throw _ServerResetToZeroException(
            'Server file changed (ETag mismatch: ${probe.etag} vs $etag)',
            newEtag: probe.etag,
            newLastModified: probe.lastModified,
            newTotalBytes: probe.totalBytes,
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

      // Verify sufficient free disk space before allocating
      if (totalBytes > 0) {
        final checker = diskSpaceChecker ?? defaultDiskSpaceChecker;
        final freeBytes = await checker(file.parent.path);
        if (freeBytes >= 0 && freeBytes < totalBytes) {
          throw FileSystemException(
            'Insufficient disk space: need $totalBytes bytes, but only $freeBytes bytes available',
            savePath,
          );
        }
      }

      // Step 2: Open file and preallocate
      if (writerFactory != null) {
        _writer = await writerFactory!(file);
      } else {
        final raf = await file.open(mode: FileMode.append);
        _writer = ConcurrentFileWriter(raf);
      }
      if (totalBytes > 0) {
        await _writer!.preallocate(totalBytes);
      }

      // Step 3: Segment Planning with global per-host connection limiter
      final availableSlots = hostPool.availableSlots(uri.host);
      final hostCap = min(maxConnectionsPerHost, hostPool.maxConnectionsPerHost);
      final effectiveConnections = (isRangeSupported && totalBytes > 256 * 1024)
          ? connectionCount.clamp(1, max(1, min(availableSlots, hostCap))).toInt()
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

      // Periodic checkpoint timer: guarantees onCheckpoint is invoked during normal progress,
      // strictly preceded by _writer.flush()
      checkpointTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_isPaused && !_isCancelled) {
          try {
            await checkpoint();
          } catch (_) {}
        }
      });

      await Future.wait(workerFutures);
      checkpointTimer.cancel();
      await checkpoint();
    } on _ServerResetToZeroException catch (resetEx) {
      checkpointTimer?.cancel();
      _log('INFO', '${resetEx.message}; restarting cleanly from byte 0');
      for (final req in _activeRequests) {
        try {
          req.abort();
        } catch (_) {}
      }
      for (final cl in _activeClients) {
        try {
          cl.close(force: true);
        } catch (_) {}
      }
      try {
        await _writer?.close();
      } catch (_) {}
      final resetRaf = await file.open(mode: FileMode.write);
      await resetRaf.truncate(0);
      await resetRaf.close();

      if (resetEx.newEtag != null) etag = resetEx.newEtag;
      if (resetEx.newLastModified != null) lastModified = resetEx.newLastModified;
      if (resetEx.newTotalBytes != null && resetEx.newTotalBytes! > 0) totalBytes = resetEx.newTotalBytes!;
      segments.clear();

      return start();
    } finally {
      checkpointTimer?.cancel();
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
    int retryCount = 0;
    const int maxRetries = 3;

    while (!segment.isFinished && !_isPaused && !_isCancelled) {
      final client = clientFactory();
      _activeClients.add(client);
      final releaseHostSlot = hostPool.acquire(uri.host);

      try {
        final request = await client.openUrl('GET', uri);
        _activeRequests.add(request);
        request.headers.set(HttpHeaders.userAgentHeader, _defaultUserAgent);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

        final startOffset = segment.currentOffset;
        final endOffset = segment.endByte;

        // RFC 7232 § 2.3 & RFC 7233 § 3.2: Only strong ETag (not starting with W/) or Last-Modified
        String? ifRangeValidator;
        if (NetGetUtils.isStrongEtag(etag)) {
          ifRangeValidator = etag!;
        } else if (lastModified != null && lastModified!.trim().isNotEmpty) {
          ifRangeValidator = lastModified!;
        }

        // If resuming a sub-range (startOffset > 0) without a valid strong validator, resumption is unsafe:
        // restart cleanly from byte 0.
        if (startOffset > 0 && ifRangeValidator == null) {
          throw _ServerResetToZeroException(
            'Cannot resume from offset $startOffset without strong ETag or Last-Modified validator. Restarting from byte 0.',
          );
        }

        if (isRangeSupported && endOffset >= startOffset) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-$endOffset');
          if (ifRangeValidator != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, ifRangeValidator);
          }
        }

        final response = await request.close();
        final statusCode = response.statusCode;

        if (statusCode == HttpStatus.tooManyRequests || statusCode == HttpStatus.serviceUnavailable) {
          if (retryCount >= maxRetries) {
            throw HttpException('HTTP $statusCode after $maxRetries retries', uri: uri);
          }
          final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
          final delay = _calculateRetryDelay(statusCode, retryAfter, retryCount);
          _log('WARN', 'Worker received HTTP $statusCode. Retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/$maxRetries)...');
          retryCount++;
          await response.drain<void>();
          await Future.delayed(delay);
          continue;
        }

        // Reset retry count on valid response
        retryCount = 0;

        // Check for ETag validation across connections
        final respEtag = response.headers.value(HttpHeaders.etagHeader);
        if (etag != null && respEtag != null && respEtag != etag) {
          throw HttpException('Server file changed (ETag mismatch: $respEtag vs $etag)', uri: uri);
        }

        if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          if (totalBytes > 0 && startOffset < totalBytes) {
            throw HttpException(
              'HTTP 416 Range Not Satisfiable for range bytes=$startOffset-$endOffset (total: $totalBytes)',
              uri: uri,
            );
          }
          segment.isCompleted = true;
          return;
        }

        if (statusCode == HttpStatus.ok) {
          if (startOffset > 0) {
            // RFC 7233 § 3.2: Server ignored Range or If-Range validator failed -> returned entire representation (200 OK).
            // Clean restart from byte 0 rather than error loop!
            final serverEtag = response.headers.value(HttpHeaders.etagHeader);
            final serverLastMod = response.headers.value(HttpHeaders.lastModifiedHeader);
            final serverLen = response.contentLength;
            await response.drain<void>();
            throw _ServerResetToZeroException(
              'Server returned HTTP 200 OK to range request (restarting cleanly from byte 0)',
              newEtag: serverEtag,
              newLastModified: serverLastMod,
              newTotalBytes: serverLen > 0 ? serverLen : null,
            );
          }
        }

        if (statusCode == HttpStatus.partialContent) {
          // Validate 206 Content-Range start equals requested start
          final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
          if (contentRange != null && contentRange.startsWith('bytes ')) {
            final rangePart = contentRange.substring(6).split('/')[0].trim();
            final rangeParts = rangePart.split('-');
            if (rangeParts.isNotEmpty) {
              final actualStart = int.tryParse(rangeParts[0]);
              if (actualStart != null && actualStart != startOffset) {
                await response.drain<void>();
                throw HttpException(
                  'Server returned unexpected Content-Range start: $actualStart != requested $startOffset',
                  uri: uri,
                );
              }
            }
          }
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
      } catch (e) {
        if (_isPaused || _isCancelled) return;
        rethrow;
      } finally {
        releaseHostSlot();
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
    // Guarantee file flush before any checkpointing or closing
    await _writer?.flush();
    if (onCheckpoint != null) {
      final snapshot = segments.map((s) => s.copyWith()).toList();
      await onCheckpoint!(snapshot);
    }
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

class _ServerResetToZeroException implements Exception {
  final String message;
  final String? newEtag;
  final String? newLastModified;
  final int? newTotalBytes;

  _ServerResetToZeroException(
    this.message, {
    this.newEtag,
    this.newLastModified,
    this.newTotalBytes,
  });

  @override
  String toString() => '_ServerResetToZeroException: $message';
}
