import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

enum ValidatorMode { strongEtag, weakEtag, lastModifiedOnly, none }

enum RangeSupportMode { supported, unsupported, chunkedNoRange }

class TestServerRequestLog {
  final int requestIndex;
  final String method;
  final Uri uri;
  final Map<String, String> headers;

  TestServerRequestLog({
    required this.requestIndex,
    required this.method,
    required this.uri,
    required this.headers,
  });
}

/// Fully configurable HTTP Test Server fixture for NetGet reliability tests and regression characterization.
class NetGetTestServer {
  final int port;
  HttpServer? _server;

  Uint8List _data;
  late String _sha256Hash;

  ValidatorMode validatorMode;
  RangeSupportMode rangeSupportMode;
  String strongEtag;
  String weakEtag;
  DateTime lastModified;

  bool ignoreRangeOnMismatchingIfRange;
  bool disallowHead; // returns 405 Method Not Allowed
  int? throttleBytesPerSec;
  Duration? stallDuration;
  int? stallAfterBytes;

  // Connection drop simulation
  int? dropAfterBytes;
  int? dropOnlyForOffset;
  int droppedConnectionsCount = 0;

  // Status injection by request count (1-based index)
  final Map<int, int> statusInjectionByRequest = {};
  final Map<int, Map<String, String>> headersInjectionByRequest = {};

  // ETag or content flip
  String? nextEtag;
  int? flipEtagOnRequest;
  Uint8List? nextData;
  int? flipDataOnRequest;

  // Redirect handling
  bool redirectEnabled;
  int redirectExpirationAfterRequests;
  int redirectRequestCount = 0;

  int requestCount = 0;
  final List<TestServerRequestLog> requestHistory = [];

  NetGetTestServer({
    this.port = 0,
    int dataSize = 2 * 1024 * 1024, // 2 MB default
    this.validatorMode = ValidatorMode.strongEtag,
    this.rangeSupportMode = RangeSupportMode.supported,
    this.strongEtag = '"netget-strong-v1"',
    this.weakEtag = 'W/"netget-weak-v1"',
    DateTime? lastModified,
    this.ignoreRangeOnMismatchingIfRange = true,
    this.disallowHead = false,
    this.throttleBytesPerSec,
    this.stallDuration,
    this.stallAfterBytes,
    this.dropAfterBytes,
    this.dropOnlyForOffset,
    this.redirectEnabled = false,
    this.redirectExpirationAfterRequests = 1,
    Uint8List? customData,
  }) : lastModified = lastModified ?? DateTime.utc(2026, 1, 1, 12, 0, 0),
       _data = customData ?? _generateDeterministicData(dataSize, 42) {
    _updateHash();
  }

  static Uint8List _generateDeterministicData(int size, int seed) {
    final data = Uint8List(size);
    final random = Random(seed);
    for (int i = 0; i < size; i++) {
      data[i] = random.nextInt(256);
    }
    return data;
  }

  void _updateHash() {
    _sha256Hash = sha256.convert(_data).toString();
  }

  Uint8List get data => _data;
  String get sha256Hash => _sha256Hash;
  int get actualPort => _server?.port ?? port;
  Uri get downloadUri => Uri.parse('http://127.0.0.1:$actualPort/download');
  Uri get redirectUri => Uri.parse('http://127.0.0.1:$actualPort/redirect');

  void updateData(Uint8List newData, {String? newEtag}) {
    _data = newData;
    _updateHash();
    if (newEtag != null) {
      strongEtag = newEtag;
    }
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  void _handleRequest(HttpRequest request) async {
    requestCount++;
    final currentReqIndex = requestCount;

    final headerMap = <String, String>{};
    request.headers.forEach((name, values) {
      headerMap[name.toLowerCase()] = values.join(', ');
    });

    requestHistory.add(
      TestServerRequestLog(
        requestIndex: currentReqIndex,
        method: request.method,
        uri: request.uri,
        headers: headerMap,
      ),
    );

    final path = request.uri.path;

    // Health probe
    if (path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('OK');
      await request.response.close();
      return;
    }

    // HEAD method check
    if (request.method == 'HEAD' && disallowHead) {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET');
      await request.response.close();
      return;
    }

    // Redirect simulation: /redirect -> /download-expired or /download
    if (path == '/redirect') {
      redirectRequestCount++;
      request.response.statusCode = HttpStatus.found;
      final target =
          'http://127.0.0.1:$actualPort/redirect-target?req=$redirectRequestCount';
      request.response.headers.set(HttpHeaders.locationHeader, target);
      await request.response.close();
      return;
    }

    if (path == '/redirect-target') {
      final reqParam =
          int.tryParse(request.uri.queryParameters['req'] ?? '1') ?? 1;
      if (reqParam > redirectExpirationAfterRequests) {
        request.response.statusCode =
            HttpStatus.forbidden; // 403 or 410 expired
        request.response.write('Redirect signature expired');
        await request.response.close();
        return;
      }
      // Serve data for valid redirect target
    }

    // Injected status code
    if (statusInjectionByRequest.containsKey(currentReqIndex)) {
      final injectedStatus = statusInjectionByRequest[currentReqIndex]!;
      request.response.statusCode = injectedStatus;
      final injectedHeaders = headersInjectionByRequest[currentReqIndex];
      if (injectedHeaders != null) {
        injectedHeaders.forEach((k, v) => request.response.headers.set(k, v));
      }
      if (injectedStatus == HttpStatus.tooManyRequests &&
          !request.response.headers.chunkedTransferEncoding &&
          request.response.headers.value(HttpHeaders.retryAfterHeader) ==
              null) {
        request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      }
      await request.response.close();
      return;
    }

    // Check ETag flip
    if (flipEtagOnRequest != null && currentReqIndex >= flipEtagOnRequest!) {
      if (nextEtag != null) {
        strongEtag = nextEtag!;
      }
    }

    // Check Data flip
    if (flipDataOnRequest != null && currentReqIndex >= flipDataOnRequest!) {
      if (nextData != null) {
        _data = nextData!;
        _updateHash();
      }
    }

    // Determine validators to send
    String? effectiveEtag;
    switch (validatorMode) {
      case ValidatorMode.strongEtag:
        effectiveEtag = strongEtag;
        break;
      case ValidatorMode.weakEtag:
        effectiveEtag = weakEtag;
        break;
      case ValidatorMode.lastModifiedOnly:
      case ValidatorMode.none:
        effectiveEtag = null;
        break;
    }

    final hasLastModified =
        validatorMode != ValidatorMode.none &&
        validatorMode != ValidatorMode.weakEtag;

    // Check If-Range header
    final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
    bool ifRangeMismatch = false;
    if (ifRange != null) {
      if (effectiveEtag != null) {
        // If-Range with strong validator
        if (ifRange != effectiveEtag) {
          ifRangeMismatch = true;
        }
      } else if (hasLastModified) {
        try {
          final ifRangeDate = HttpDate.parse(ifRange);
          if (ifRangeDate.isBefore(lastModified)) {
            ifRangeMismatch = true;
          }
        } catch (_) {
          ifRangeMismatch = true;
        }
      } else {
        // Server has no validator, mismatch
        ifRangeMismatch = true;
      }
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    // If Range header requested and If-Range mismatched, return 200 OK full body
    if (rangeHeader != null &&
        ifRangeMismatch &&
        ignoreRangeOnMismatchingIfRange) {
      await _sendFullResponse(
        request,
        effectiveEtag,
        hasLastModified,
        forceChunked: rangeSupportMode == RangeSupportMode.chunkedNoRange,
      );
      return;
    }

    // No range support mode
    if (rangeSupportMode == RangeSupportMode.unsupported) {
      await _sendFullResponse(
        request,
        effectiveEtag,
        hasLastModified,
        forceChunked: false,
      );
      return;
    }

    // Chunked unknown length mode
    if (rangeSupportMode == RangeSupportMode.chunkedNoRange) {
      await _sendFullResponse(
        request,
        effectiveEtag,
        hasLastModified,
        forceChunked: true,
      );
      return;
    }

    // Normal Range handling (206 Partial Content)
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6).trim();
      final parts = spec.split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = (parts.length > 1 && parts[1].isNotEmpty)
          ? int.tryParse(parts[1]) ?? (_data.length - 1)
          : (_data.length - 1);

      if (start >= _data.length || end < start) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${_data.length}',
        );
        await request.response.close();
        return;
      }

      final clampedEnd = min(end, _data.length - 1);
      final length = clampedEnd - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (effectiveEtag != null) {
        request.response.headers.set(HttpHeaders.etagHeader, effectiveEtag);
      }
      if (hasLastModified) {
        request.response.headers.set(
          HttpHeaders.lastModifiedHeader,
          HttpDate.format(lastModified),
        );
      }
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$clampedEnd/${_data.length}',
      );
      request.response.headers.contentLength = length;
      request.response.headers.contentType = ContentType.binary;

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      // Check if we should drop connection or stall
      final shouldDropForOffset =
          dropOnlyForOffset == null || dropOnlyForOffset == start;
      await _streamBody(
        request,
        _data.sublist(start, clampedEnd + 1),
        shouldDrop: dropAfterBytes != null && shouldDropForOffset,
        dropBytes: dropAfterBytes,
      );
      return;
    }

    // Standard Full response (200 OK)
    await _sendFullResponse(
      request,
      effectiveEtag,
      hasLastModified,
      forceChunked: false,
    );
  }

  Future<void> _sendFullResponse(
    HttpRequest request,
    String? etag,
    bool sendLastModified, {
    required bool forceChunked,
  }) async {
    request.response.statusCode = HttpStatus.ok;
    if (rangeSupportMode == RangeSupportMode.supported) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    } else {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    }

    if (etag != null) {
      request.response.headers.set(HttpHeaders.etagHeader, etag);
    }
    if (sendLastModified) {
      request.response.headers.set(
        HttpHeaders.lastModifiedHeader,
        HttpDate.format(lastModified),
      );
    }

    request.response.headers.contentType = ContentType.binary;

    if (forceChunked) {
      // Chunked: no Content-Length header
      request.response.headers.chunkedTransferEncoding = true;
    } else {
      request.response.headers.contentLength = _data.length;
    }

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    await _streamBody(
      request,
      _data,
      shouldDrop: dropAfterBytes != null && dropOnlyForOffset == null,
      dropBytes: dropAfterBytes,
    );
  }

  Future<void> _streamBody(
    HttpRequest request,
    Uint8List payload, {
    required bool shouldDrop,
    int? dropBytes,
  }) async {
    const defaultChunkSize = 32 * 1024;
    int bytesSent = 0;
    int offset = 0;

    while (offset < payload.length) {
      final remaining = payload.length - offset;
      final chunkSize = min(defaultChunkSize, remaining);

      // Stall check
      if (stallDuration != null &&
          stallAfterBytes != null &&
          bytesSent >= stallAfterBytes!) {
        await Future<void>.delayed(stallDuration!);
        stallDuration = null; // Stall once
      }

      // Drop connection check mid-stream
      if (shouldDrop &&
          dropBytes != null &&
          (bytesSent + chunkSize) >= dropBytes) {
        final partial = dropBytes - bytesSent;
        if (partial > 0) {
          request.response.add(payload.sublist(offset, offset + partial));
          await request.response.flush();
        }
        droppedConnectionsCount++;
        // Abruptly detach and destroy socket (RST / connection reset by peer)
        try {
          final socket = await request.response.detachSocket();
          socket.destroy();
        } catch (_) {
          try {
            await request.response.close();
          } catch (_) {}
        }
        return;
      }

      final chunk = payload.sublist(offset, offset + chunkSize);
      request.response.add(chunk);
      bytesSent += chunk.length;
      offset += chunk.length;

      // Bandwidth shaping (throttle)
      if (throttleBytesPerSec != null && throttleBytesPerSec! > 0) {
        final delayMs = ((chunkSize / throttleBytesPerSec!) * 1000).round();
        if (delayMs > 0) {
          await request.response.flush();
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    try {
      await request.response.close();
    } catch (_) {}
  }
}
