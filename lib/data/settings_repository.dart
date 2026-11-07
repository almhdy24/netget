import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/utils.dart';

/// Repository responsible for persisting app-level preferences (e.g. theme mode)
/// into a local atomic JSON file (`netget_settings.json`).
class SettingsRepository {
  final File? _customFile;
  File? _resolvedFile;

  SettingsRepository({File? file}) : _customFile = file;

  Future<File> _getFile() async {
    if (_customFile != null) return _customFile;
    if (_resolvedFile != null) return _resolvedFile!;

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'netget_settings.json'));
    _resolvedFile = file;
    return file;
  }

  /// Loads the persisted [ThemeMode]. Defaults to [ThemeMode.system] if not set.
  Future<ThemeMode> loadThemeMode() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return ThemeMode.system;
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) return ThemeMode.system;

      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final modeString = decoded['themeMode'] as String?;
        switch (modeString) {
          case 'light':
            return ThemeMode.light;
          case 'dark':
            return ThemeMode.dark;
          case 'system':
          default:
            return ThemeMode.system;
        }
      }
    } catch (_) {
      // Fallback gracefully on parsing/read error
    }
    return ThemeMode.system;
  }

  /// Persists [ThemeMode] atomically using temporary file and safe rename.
  Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final file = await _getFile();
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              data = decoded;
            }
          }
        } catch (_) {}
      }

      String modeStr;
      switch (mode) {
        case ThemeMode.light:
          modeStr = 'light';
          break;
        case ThemeMode.dark:
          modeStr = 'dark';
          break;
        case ThemeMode.system:
          modeStr = 'system';
          break;
      }

      data['themeMode'] = modeStr;
      data['updatedAt'] = DateTime.now().toIso8601String();

      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(jsonEncode(data), flush: true);
      await NetGetUtils.safeRenameFile(tempFile, file);
    } catch (_) {
      // Ignore write errors gracefully
    }
  }
}
