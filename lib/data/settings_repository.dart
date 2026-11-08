import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/utils.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  final File? _customFile;
  File? _resolvedFile;
  AppSettings? _cachedSettings;
  Future<void> _writeQueue = Future.value();

  SettingsRepository({File? file}) : _customFile = file;

  Future<File> _getFile() async {
    if (_customFile != null) return _customFile;
    if (_resolvedFile != null) return _resolvedFile!;

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'netget_settings.json'));
    _resolvedFile = file;
    return file;
  }

  Future<AppSettings> load() async {
    if (_cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cachedSettings = const AppSettings();
        return _cachedSettings!;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _cachedSettings = const AppSettings();
        return _cachedSettings!;
      }

      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _cachedSettings = AppSettings.fromJson(decoded);
        return _cachedSettings!;
      }
    } catch (e, st) {
      debugPrint('Failed to load settings from disk: $e\n$st');
    }

    _cachedSettings = const AppSettings();
    return _cachedSettings!;
  }

  Future<void> save(AppSettings settings) {
    _cachedSettings = settings;

    // Serialize writes through the future queue
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _getFile();
        final raw = const JsonEncoder.withIndent(
          '  ',
        ).convert(settings.toJson());
        final tempFile = File('${file.path}.tmp');

        await tempFile.writeAsString(raw, flush: true);
        if (await tempFile.exists()) {
          await NetGetUtils.safeRenameFile(tempFile, file);
        }
      } catch (e, st) {
        debugPrint('Failed to persist settings to disk: $e\n$st');
      }
    });

    return _writeQueue;
  }

  // Backwards compatibility helpers
  Future<AppSettings> loadSettings() => load();
  Future<void> saveSettings(AppSettings settings) => save(settings);

  Future<ThemeMode> loadThemeMode() async {
    final s = await load();
    return s.themeMode;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final current = await load();
    await save(current.copyWith(themeMode: mode));
  }

  Future<bool> loadAnalyticsEnabled() async {
    final s = await load();
    return s.analyticsEnabled;
  }

  Future<void> saveAnalyticsEnabled(bool enabled) async {
    final current = await load();
    await save(current.copyWith(analyticsEnabled: enabled));
  }
}
