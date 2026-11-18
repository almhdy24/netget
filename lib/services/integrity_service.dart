import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class SidecarResult {
  final String checksum;
  final String algorithm;

  const SidecarResult({required this.checksum, required this.algorithm});
}

/// Standalone top-level isolate function for chunked file checksum calculation.
/// Keeps the UI thread 100% fluid even on multi-gigabyte downloads.
Future<String> computeFileChecksumIsolated(Map<String, String> args) async {
  final filePath = args['path']!;
  final algorithm = args['algorithm']?.toLowerCase() ?? 'sha256';

  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('Target file does not exist', filePath);
  }

  final Hash hasher;
  if (algorithm == 'md5') {
    hasher = md5;
  } else if (algorithm == 'sha1') {
    hasher = sha1;
  } else {
    hasher = sha256;
  }

  final digest = await hasher.bind(file.openRead()).single;
  return digest.toString();
}

class IntegrityService {
  final HttpClient Function()? clientFactory;

  IntegrityService({this.clientFactory});

  HttpClient _createClient() {
    if (clientFactory != null) return clientFactory!();
    return HttpClient()..connectionTimeout = const Duration(seconds: 8);
  }

  /// Calculates SHA-256, SHA-1, or MD5 in a background isolate.
  Future<String> computeChecksum({
    required String filePath,
    String algorithm = 'sha256',
  }) async {
    return compute(computeFileChecksumIsolated, {
      'path': filePath,
      'algorithm': algorithm,
    });
  }

  /// Probes for sidecar checksum files (`<url>.sha256`, `<url>.md5`, `<url>.sha1`).
  /// If found, parses the checksum string and detected algorithm.
  Future<SidecarResult?> probeSidecarChecksum(String downloadUrl) async {
    final client = _createClient();
    final candidates = [
      {'ext': '.sha256', 'alg': 'sha256', 'len': 64},
      {'ext': '.md5', 'alg': 'md5', 'len': 32},
      {'ext': '.sha1', 'alg': 'sha1', 'len': 40},
    ];

    try {
      for (final candidate in candidates) {
        final ext = candidate['ext'] as String;
        final alg = candidate['alg'] as String;
        final hexLen = candidate['len'] as int;

        final sidecarUri = Uri.parse('$downloadUrl$ext');
        try {
          final req = await client.getUrl(sidecarUri);
          final resp = await req.close();
          if (resp.statusCode == 200) {
            final content = await utf8.decoder.bind(resp).join();
            if (content.length < 2048) {
              final hexPattern = RegExp('\\b[a-fA-F0-9]{$hexLen}\\b');
              final match = hexPattern.firstMatch(content);
              if (match != null) {
                return SidecarResult(
                  checksum: match.group(0)!.toLowerCase(),
                  algorithm: alg,
                );
              }
            }
          }
        } catch (_) {
          // Continue trying other candidates
        }
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Verifies actual checksum against expected checksum case-insensitively.
  static bool verify(String? expected, String? actual) {
    if (expected == null || actual == null) return false;
    final expClean = expected.trim().toLowerCase();
    final actClean = actual.trim().toLowerCase();
    if (expClean.isEmpty || actClean.isEmpty) return false;
    return expClean == actClean;
  }
}
