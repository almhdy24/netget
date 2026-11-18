import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'data_budget.dart';

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
  final bool autoResumeInterrupted;
  final bool autoResumeOnBoot;
  final int? monthlyBudgetBytes;
  final int budgetResetDay;
  final int warningThresholdPercent;
  final bool budgetHardStop;
  final List<FreeWindow> freeWindows;
  final NetworkPolicy defaultNetworkPolicy;
  final bool useEasternArabicDigits;

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
    this.autoResumeInterrupted = true,
    this.autoResumeOnBoot = false,
    this.monthlyBudgetBytes,
    this.budgetResetDay = 1,
    this.warningThresholdPercent = 80,
    this.budgetHardStop = true,
    this.freeWindows = const [],
    this.defaultNetworkPolicy = NetworkPolicy.anyNetwork,
    this.useEasternArabicDigits = false,
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
    bool? autoResumeInterrupted,
    bool? autoResumeOnBoot,
    int? monthlyBudgetBytes,
    int? budgetResetDay,
    int? warningThresholdPercent,
    bool? budgetHardStop,
    List<FreeWindow>? freeWindows,
    NetworkPolicy? defaultNetworkPolicy,
    bool? useEasternArabicDigits,
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
      autoResumeInterrupted:
          autoResumeInterrupted ?? this.autoResumeInterrupted,
      autoResumeOnBoot: autoResumeOnBoot ?? this.autoResumeOnBoot,
      monthlyBudgetBytes: monthlyBudgetBytes ?? this.monthlyBudgetBytes,
      budgetResetDay: budgetResetDay ?? this.budgetResetDay,
      warningThresholdPercent:
          warningThresholdPercent ?? this.warningThresholdPercent,
      budgetHardStop: budgetHardStop ?? this.budgetHardStop,
      freeWindows: freeWindows ?? this.freeWindows,
      defaultNetworkPolicy: defaultNetworkPolicy ?? this.defaultNetworkPolicy,
      useEasternArabicDigits:
          useEasternArabicDigits ?? this.useEasternArabicDigits,
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
    'autoResumeInterrupted': autoResumeInterrupted,
    'autoResumeOnBoot': autoResumeOnBoot,
    'monthlyBudgetBytes': monthlyBudgetBytes,
    'budgetResetDay': budgetResetDay,
    'warningThresholdPercent': warningThresholdPercent,
    'budgetHardStop': budgetHardStop,
    'freeWindows': freeWindows.map((w) => w.toJson()).toList(),
    'defaultNetworkPolicy': defaultNetworkPolicy.name,
    'useEasternArabicDigits': useEasternArabicDigits,
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

    final freeWindowsList =
        (json['freeWindows'] as List<dynamic>?)
            ?.map((e) => FreeWindow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <FreeWindow>[];

    final policyStr = json['defaultNetworkPolicy'] as String?;
    final parsedPolicy = NetworkPolicy.fromString(policyStr);

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
      autoResumeInterrupted: json['autoResumeInterrupted'] as bool? ?? true,
      autoResumeOnBoot: json['autoResumeOnBoot'] as bool? ?? false,
      monthlyBudgetBytes: json['monthlyBudgetBytes'] as int?,
      budgetResetDay: json['budgetResetDay'] as int? ?? 1,
      warningThresholdPercent: json['warningThresholdPercent'] as int? ?? 80,
      budgetHardStop: json['budgetHardStop'] as bool? ?? true,
      freeWindows: freeWindowsList,
      defaultNetworkPolicy: parsedPolicy,
      useEasternArabicDigits: json['useEasternArabicDigits'] as bool? ?? false,
    );
  }
}
