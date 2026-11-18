import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class NearbyShareUpdate {
  final int activePeers;
  final int transferredBytes;
  final int totalBytes;
  final bool isRunning;

  const NearbyShareUpdate({
    required this.activePeers,
    required this.transferredBytes,
    required this.totalBytes,
    required this.isRunning,
  });
}

/// In-app local HTTP server for sharing downloaded files with peers over
/// Wi-Fi or portable hotspot («شارك بالقرب»).
class NearbyShareService {
  HttpServer? _server;
  File? _sharedFile;
  String? _token;
  String? _ipAddress;
  int _port = 0;
  int _fileSize = 0;
  String _fileName = '';

  int _activePeers = 0;
  int _transferredBytes = 0;
  Timer? _inactivityTimer;

  static const Duration inactivityTimeout = Duration(minutes: 15);

  final _updateController = StreamController<NearbyShareUpdate>.broadcast();
  Stream<NearbyShareUpdate> get updates => _updateController.stream;

  bool get isSharing => _server != null;
  String? get shareUrl =>
      isSharing ? 'http://$_ipAddress:$_port/d/$_token/$_fileName' : null;
  String? get ipAddress => _ipAddress;
  int get port => _port;
  String get fileName => _fileName;
  int get fileSize => _fileSize;
  int get activePeers => _activePeers;
  int get transferredBytes => _transferredBytes;

  /// Starts a local HTTP sharing server for [file].
  Future<String> startSharing(
    File file, {
    String? customFileName,
    String? explicitIp,
  }) async {
    if (_server != null) {
      await stopSharing();
    }

    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }

    _sharedFile = file;
    _fileSize = await file.length();
    _fileName = customFileName ?? file.uri.pathSegments.last;
    _token = (DateTime.now().millisecondsSinceEpoch % 1000000).toString();
    _transferredBytes = 0;
    _activePeers = 0;

    _ipAddress = explicitIp ?? await resolveLocalIpAddress();

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;

    _resetInactivityTimer();
    _listenRequests();

    _emitUpdate();
    return shareUrl!;
  }

  /// Stops and tears down the local HTTP server.
  Future<void> stopSharing() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    final server = _server;
    _server = null;
    _sharedFile = null;
    _token = null;
    _activePeers = 0;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    _emitUpdate();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, () {
      stopSharing();
    });
  }

  void _emitUpdate() {
    if (!_updateController.isClosed) {
      _updateController.add(
        NearbyShareUpdate(
          activePeers: _activePeers,
          transferredBytes: _transferredBytes,
          totalBytes: _fileSize,
          isRunning: isSharing,
        ),
      );
    }
  }

  void _listenRequests() {
    _server?.listen((HttpRequest request) async {
      _resetInactivityTimer();
      final path = request.uri.path;
      final expectedPath = '/d/$_token/$_fileName';

      // Route match check (URL decoding handled)
      final decodedPath = Uri.decodeComponent(path);
      if (decodedPath != expectedPath && path != expectedPath) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
        return;
      }

      if (_sharedFile == null || !await _sharedFile!.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('File removed or unavailable');
        await request.response.close();
        return;
      }

      final method = request.method;
      if (method != 'GET' && method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await request.response.close();
        return;
      }

      _activePeers++;
      _emitUpdate();

      try {
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="$_fileName"',
        );
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/octet-stream',
        );

        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          // Range request support (RFC 7233)
          final rangePart = rangeHeader.substring(6).trim();
          final parts = rangePart.split('-');
          int start = 0;
          int end = _fileSize - 1;

          if (parts[0].isNotEmpty) {
            start = int.tryParse(parts[0]) ?? 0;
          }
          if (parts.length > 1 && parts[1].isNotEmpty) {
            end = int.tryParse(parts[1]) ?? (_fileSize - 1);
          }

          if (start > end || start >= _fileSize) {
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes */$_fileSize',
            );
            await request.response.close();
            return;
          }

          if (end >= _fileSize) {
            end = _fileSize - 1;
          }

          final contentLength = end - start + 1;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$_fileSize',
          );
          request.response.contentLength = contentLength;

          if (method == 'HEAD') {
            await request.response.close();
            return;
          }

          final raf = await _sharedFile!.open(mode: FileMode.read);
          try {
            await raf.setPosition(start);
            int remaining = contentLength;
            const bufferSize = 64 * 1024;

            while (remaining > 0) {
              final toRead = remaining < bufferSize ? remaining : bufferSize;
              final buffer = await raf.read(toRead);
              if (buffer.isEmpty) break;
              request.response.add(buffer);
              remaining -= buffer.length;
              _transferredBytes += buffer.length;
              _emitUpdate();
            }
          } finally {
            await raf.close();
          }
        } else {
          // Standard full representation
          request.response.statusCode = HttpStatus.ok;
          request.response.contentLength = _fileSize;

          if (method == 'HEAD') {
            await request.response.close();
            return;
          }

          final stream = _sharedFile!.openRead();
          await for (final chunk in stream) {
            request.response.add(chunk);
            _transferredBytes += chunk.length;
            _emitUpdate();
          }
        }

        await request.response.close();
      } catch (e) {
        debugPrint('NearbyShare error serving request: $e');
      } finally {
        _activePeers = (_activePeers > 0) ? _activePeers - 1 : 0;
        _emitUpdate();
      }
    });
  }

  /// Detects the best IPv4 address for local network / hotspot sharing.
  static Future<String> resolveLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // Prioritize hotspot/softap and wlan interfaces
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('ap') ||
            name.contains('hotspot') ||
            name.contains('wlan')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // Fallback to any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return '127.0.0.1';
  }

  void dispose() {
    stopSharing();
    _updateController.close();
  }
}
