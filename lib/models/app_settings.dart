import 'package:flutter/material.dart';
import '../core/constants.dart';

class AppSettings {
  final ThemeMode themeMode;
  final String language; // 'system', 'ar', 'en'
  final bool analyticsEnabled;
  final bool analyticsPromptShown;
  final int maxConcurrent;
  final int connectionsPerDownload;
  final SpeedMode speedMode;
  final bool wifiOnly;
  final bool soundsEnabled;
  final String? defaultFolder;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = 'system',
    this.analyticsEnabled = false,
    this.analyticsPromptShown = false,
    this.maxConcurrent = NetGetConstants.maxConcurrentDownloads,
    this.connectionsPerDownload = NetGetConstants.defaultConnections,
    this.speedMode = SpeedMode.unlimited,
    this.wifiOnly = false,
    this.soundsEnabled = true,
    this.defaultFolder,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? language,
    bool? analyticsEnabled,
    bool? analyticsPromptShown,
    int? maxConcurrent,
    int? connectionsPerDownload,
    SpeedMode? speedMode,
    bool? wifiOnly,
    bool? soundsEnabled,
    String? defaultFolder,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      analyticsPromptShown: analyticsPromptShown ?? this.analyticsPromptShown,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      connectionsPerDownload:
          connectionsPerDownload ?? this.connectionsPerDownload,
      speedMode: speedMode ?? this.speedMode,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      soundsEnabled: soundsEnabled ?? this.soundsEnabled,
      defaultFolder: defaultFolder ?? this.defaultFolder,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'language': language,
    'analyticsEnabled': analyticsEnabled,
    'analyticsPromptShown': analyticsPromptShown,
    'maxConcurrent': maxConcurrent,
    'connectionsPerDownload': connectionsPerDownload,
    'speedMode': speedMode.name,
    'wifiOnly': wifiOnly,
    'soundsEnabled': soundsEnabled,
    'defaultFolder': defaultFolder,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    ThemeMode parsedTheme = ThemeMode.system;
    final themeStr = json['themeMode'] as String?;
    if (themeStr != null) {
      parsedTheme = ThemeMode.values.firstWhere(
        (m) => m.name == themeStr,
        orElse: () => ThemeMode.system,
      );
    }

    SpeedMode parsedSpeed = SpeedMode.unlimited;
    final speedStr = json['speedMode'] as String?;
    if (speedStr != null) {
      parsedSpeed = SpeedMode.values.firstWhere(
        (s) => s.name == speedStr,
        orElse: () => SpeedMode.unlimited,
      );
    }

    return AppSettings(
      themeMode: parsedTheme,
      language: json['language'] as String? ?? 'system',
      analyticsEnabled: json['analyticsEnabled'] as bool? ?? false,
      analyticsPromptShown: json['analyticsPromptShown'] as bool? ?? false,
      maxConcurrent:
          json['maxConcurrent'] as int? ??
          NetGetConstants.maxConcurrentDownloads,
      connectionsPerDownload:
          json['connectionsPerDownload'] as int? ??
          NetGetConstants.defaultConnections,
      speedMode: parsedSpeed,
      wifiOnly: json['wifiOnly'] as bool? ?? false,
      soundsEnabled: json['soundsEnabled'] as bool? ?? true,
      defaultFolder: json['defaultFolder'] as String?,
    );
  }
}
