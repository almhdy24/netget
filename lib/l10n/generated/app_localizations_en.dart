// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'NetGet';

  @override
  String get appFullName => 'NetGet Download Manager';

  @override
  String get appSubtitle => 'Fast & Reliable File Transfers';

  @override
  String get addUrl => 'Add URL';

  @override
  String get startNow => 'Start now';

  @override
  String get downloadLater => 'Download later';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get open => 'Open';

  @override
  String get openFolder => 'Open folder';

  @override
  String get copyLink => 'Copy link';

  @override
  String get shareFile => 'Share file';

  @override
  String get resumeAll => 'Resume all';

  @override
  String get pauseAll => 'Pause all';

  @override
  String get deleteSelected => 'Delete selected';

  @override
  String get selectAll => 'Select all';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String selectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get settings => 'Preferences';

  @override
  String get theme => 'Theme';

  @override
  String get appearance => 'Appearance';

  @override
  String get systemTheme => 'System default';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get privacy => 'Privacy';

  @override
  String get anonymousAnalytics => 'Anonymous usage statistics';

  @override
  String get anonymousAnalyticsDesc =>
      'Shares anonymous crash and performance metrics to improve NetGet. URLs, filenames, and personal info are never collected.';

  @override
  String get maxConcurrentDownloads => 'Max concurrent downloads';

  @override
  String get connectionsPerDownload => 'Connections per download';

  @override
  String get downloadOverWifiOnly => 'Download over Wi-Fi only';

  @override
  String get completionSoundEffects => 'Completion sound effects';

  @override
  String get speedLimiter => 'Speed limiter';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get general => 'General';

  @override
  String get segments => 'Segments';

  @override
  String get speedGraph => 'Speed Graph';

  @override
  String get log => 'Log';

  @override
  String get connectionMap => 'Connection Map';

  @override
  String get segmentDetails => 'Segment Details';

  @override
  String get copyLog => 'Copy Log';

  @override
  String get noDownloads => 'No downloads in this category';

  @override
  String get noDownloadsDesc =>
      'Add a new download URL using the toolbar above.';

  @override
  String get pasteFromClipboard => 'Paste from clipboard';

  @override
  String get categoryAll => 'All';

  @override
  String get categoryVideo => 'Video';

  @override
  String get categoryAudio => 'Audio';

  @override
  String get categoryImages => 'Images';

  @override
  String get categoryDocuments => 'Documents';

  @override
  String get categoryArchives => 'Archives';

  @override
  String get categoryApps => 'Apps';

  @override
  String get categoryOther => 'Other';
}
