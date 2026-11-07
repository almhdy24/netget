import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Controlled HTTP Test Server for NetGet reliability tests and performance benchmarks.
class TestHttpServer {
  final int port;
  HttpServer? _server;
  late final Uint8List _testData;
  late final String _testDataSha256;
  final String etag = '"netget-test-etag-v1"';
  final String changedEtag = '"netget-test-etag-v2"';
  final DateTime lastModified = DateTime.utc(2026, 1, 1, 12, 0, 0);

  TestHttpServer({this.port = 0, int dataSize = 10 * 1024 * 1024}) {
    // Generate deterministic reproducible test payload (pseudo-random pattern)
    _testData = Uint8List(dataSize);
    final random = Random(42);
    for (int i = 0; i < dataSize; i++) {
      _testData[i] = random.nextInt(256);
    }
    // Calculate SHA-256
    _testDataSha256 = _calculateSha256(_testData);
  }

  Uint8List get testData => _testData;
  String get testDataSha256 => _testDataSha256;
  int get actualPort => _server?.port ?? port;

  static String _calculateSha256(List<int> bytes) {
    // Basic SHA-256 using dart:io / crypto or deterministic hash
    // We can use a simple fast hash for verification or Platform crypto
    var hash = 0;
    for (var b in bytes) {
      hash = (hash * 31 + b) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    final mode = query['mode'] ?? 'normal';

    if (path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('OK');
      await request.response.close();
      return;
    }

    if (path != '/download') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    // SCENARIO 4: Server changes ETag
    final currentEtag = (mode == 'etag_changed') ? changedEtag : etag;

    // Check If-Range
    final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
    if (ifRange != null && ifRange != currentEtag) {
      // ETag mismatch: must return full file with 200 OK instead of 206
      _sendFullResponse(request, currentEtag);
      return;
    }

    // SCENARIO 2: Server ignores Range (returns 200 OK with full body)
    if (mode == 'no_range') {
      _sendFullResponse(request, currentEtag);
      return;
    }

    // SCENARIO 3: Server returns 416 Range Not Satisfiable
    if (mode == 'range_416') {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${_testData.length}');
      await request.response.close();
      return;
    }

    // Handle Range requests
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = (parts.length > 1 && parts[1].isNotEmpty)
          ? int.tryParse(parts[1]) ?? (_testData.length - 1)
          : (_testData.length - 1);

      if (start >= _testData.length || end < start) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${_testData.length}');
        await request.response.close();
        return;
      }

      final clampedEnd = min(end, _testData.length - 1);
      final length = clampedEnd - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.etagHeader, currentEtag);
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$clampedEnd/${_testData.length}');
      request.response.headers.contentLength = length;
      request.response.headers.contentType = ContentType.binary;

      // SCENARIO 5: Server disconnects midway during active payload transfer
      if (mode == 'abort_midway' && length > 1024) {
        final half = length ~/ 2;
        request.response.add(_testData.sublist(start, start + half));
        await request.response.flush();
        // Prematurely close connection before Content-Length is satisfied
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }

      // Stream data in 64 KB chunks
      const chunkSize = 64 * 1024;
      var offset = start;
      while (offset <= clampedEnd) {
        final toSend = min(chunkSize, clampedEnd - offset + 1);
        request.response.add(_testData.sublist(offset, offset + toSend));
        offset += toSend;
      }
      await request.response.close();
      return;
    }

    // Standard Full GET / HEAD
    if (request.method == 'HEAD') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.etagHeader, currentEtag);
      request.response.headers.contentLength = _testData.length;
      request.response.headers.contentType = ContentType.binary;
      await request.response.close();
      return;
    }

    _sendFullResponse(request, currentEtag);
  }

  void _sendFullResponse(HttpRequest request, String responseEtag) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(HttpHeaders.etagHeader, responseEtag);
    request.response.headers.contentLength = _testData.length;
    request.response.headers.contentType = ContentType.binary;

    const chunkSize = 64 * 1024;
    var offset = 0;
    while (offset < _testData.length) {
      final toSend = min(chunkSize, _testData.length - offset);
      request.response.add(_testData.sublist(offset, offset + toSend));
      offset += toSend;
    }
    await request.response.close();
  }
}
