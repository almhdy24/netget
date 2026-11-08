// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'NetGet';

  @override
  String get appFullName => 'نت جت مدير التنزيلات';

  @override
  String get appSubtitle => 'نقل ملفات سريع وموثوق';

  @override
  String get addUrl => 'إضافة رابط';

  @override
  String get startNow => 'ابدأ الآن';

  @override
  String get downloadLater => 'تنزيل لاحقاً';

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get resume => 'استئناف';

  @override
  String get open => 'فتح';

  @override
  String get openFolder => 'فتح المجلد';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get shareFile => 'مشاركة الملف';

  @override
  String get resumeAll => 'استئناف الكل';

  @override
  String get pauseAll => 'إيقاف الكل';

  @override
  String get deleteSelected => 'حذف المحدد';

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get clearSelection => 'إلغاء التحديد';

  @override
  String selectedCount(Object count) {
    return 'تم تحديد $count';
  }

  @override
  String get settings => 'الإعدادات';

  @override
  String get theme => 'المظهر';

  @override
  String get appearance => 'المظهر والسمة';

  @override
  String get systemTheme => 'تلقائي (حسب النظام)';

  @override
  String get lightTheme => 'فاتح';

  @override
  String get darkTheme => 'داكن';

  @override
  String get privacy => 'الخصوصية';

  @override
  String get anonymousAnalytics => 'إحصائيات الاستخدام المجهولة';

  @override
  String get anonymousAnalyticsDesc =>
      'تساعد في تحسين التطبيق بإرسال مقاييس الأداء والأخطاء فقط. لا يتم إرسال روابط أو أسماء ملفات أو بيانات خاصة إطلاقاً.';

  @override
  String get maxConcurrentDownloads => 'التحميلات المتزامنة القصوى';

  @override
  String get connectionsPerDownload => 'أجزاء الاتصال لكل تحميل';

  @override
  String get downloadOverWifiOnly => 'التحميل عبر واي-فاي فقط';

  @override
  String get completionSoundEffects => 'أصوات إشعار الاكتمال';

  @override
  String get speedLimiter => 'محدد السرعة';

  @override
  String get unlimited => 'غير محدود';

  @override
  String get general => 'عام';

  @override
  String get segments => 'الأجزاء';

  @override
  String get speedGraph => 'رسم السرعة';

  @override
  String get log => 'السجل';

  @override
  String get connectionMap => 'خريطة الاتصالات';

  @override
  String get segmentDetails => 'تفاصيل الأجزاء';

  @override
  String get copyLog => 'نسخ السجل';

  @override
  String get noDownloads => 'لا توجد تنزيلات في هذا القسم';

  @override
  String get noDownloadsDesc =>
      'أضف رابط تنزيل جديد باستخدام شريط الأدوات أعلاه.';

  @override
  String get pasteFromClipboard => 'لصق من الحافظة';

  @override
  String get categoryAll => 'الكل';

  @override
  String get categoryVideo => 'فيديو';

  @override
  String get categoryAudio => 'صوتيات';

  @override
  String get categoryImages => 'صور';

  @override
  String get categoryDocuments => 'مستندات';

  @override
  String get categoryArchives => 'أرشيف';

  @override
  String get categoryApps => 'تطبيقات';

  @override
  String get categoryOther => 'أخرى';
}
