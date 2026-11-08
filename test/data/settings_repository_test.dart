import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/settings_repository.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_settings_test_');
    settingsFile = File('${tempDir.path}/netget_settings.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loadThemeMode defaults to ThemeMode.system when file missing', () async {
    final repo = SettingsRepository(file: settingsFile);
    final mode = await repo.loadThemeMode();
    expect(mode, ThemeMode.system);
  });

  test('saveThemeMode and loadThemeMode persist dark, light, and system', () async {
    final repo = SettingsRepository(file: settingsFile);

    // Save dark
    await repo.saveThemeMode(ThemeMode.dark);
    expect(await repo.loadThemeMode(), ThemeMode.dark);

    // Save light
    await repo.saveThemeMode(ThemeMode.light);
    expect(await repo.loadThemeMode(), ThemeMode.light);

    // Save system
    await repo.saveThemeMode(ThemeMode.system);
    expect(await repo.loadThemeMode(), ThemeMode.system);
  });

  test('loadAnalyticsEnabled defaults to true when file missing', () async {
    final repo = SettingsRepository(file: settingsFile);
    final enabled = await repo.loadAnalyticsEnabled();
    expect(enabled, isTrue);
  });

  test('saveAnalyticsEnabled persists false and true correctly', () async {
    final repo = SettingsRepository(file: settingsFile);

    await repo.saveAnalyticsEnabled(false);
    expect(await repo.loadAnalyticsEnabled(), isFalse);

    await repo.saveAnalyticsEnabled(true);
    expect(await repo.loadAnalyticsEnabled(), isTrue);
  });
}
