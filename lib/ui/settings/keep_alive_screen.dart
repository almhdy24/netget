import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screen explaining OEM battery optimization and providing direct deep links.
/// Tagline: «ما بنبدأ من الصفر» — ensures downloads stay alive on aggressive OEM killers.
class KeepAliveScreen extends StatefulWidget {
  const KeepAliveScreen({super.key});

  @override
  State<KeepAliveScreen> createState() => _KeepAliveScreenState();
}

class _KeepAliveScreenState extends State<KeepAliveScreen> {
  static const MethodChannel _platform = MethodChannel(
    'com.elmahdi.netget/engine',
  );

  bool _loading = true;
  String _manufacturer = '';
  String _brand = '';
  String _model = '';
  bool _isBatteryOptimizationIgnored = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceOemInfo();
  }

  Future<void> _loadDeviceOemInfo() async {
    try {
      final info = await _platform.invokeMapMethod<String, dynamic>(
        'getDeviceOemInfo',
      );
      if (info != null && mounted) {
        setState(() {
          _manufacturer = (info['manufacturer'] as String? ?? '').toLowerCase();
          _brand = (info['brand'] as String? ?? '').toLowerCase();
          _model = info['model'] as String? ?? '';
          _isBatteryOptimizationIgnored =
              info['isBatteryOptimizationIgnored'] as bool? ?? false;
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      await _platform.invokeMethod('requestIgnoreBatteryOptimizations');
      await Future<void>.delayed(const Duration(seconds: 1));
      await _loadDeviceOemInfo();
    } catch (_) {}
  }

  Future<void> _openOemBatterySettings() async {
    try {
      await _platform.invokeMethod('openOemBatterySettings');
    } catch (_) {}
  }

  String _getOemDisplayName() {
    if (_manufacturer.contains('transsion') ||
        _manufacturer.contains('tecno') ||
        _brand.contains('tecno')) {
      return 'Tecno';
    }
    if (_manufacturer.contains('infinix') || _brand.contains('infinix')) {
      return 'Infinix';
    }
    if (_manufacturer.contains('itel') || _brand.contains('itel')) {
      return 'itel';
    }
    if (_manufacturer.contains('xiaomi') ||
        _manufacturer.contains('redmi') ||
        _manufacturer.contains('poco')) {
      return 'Xiaomi / Redmi';
    }
    if (_manufacturer.contains('samsung')) {
      return 'Samsung';
    }
    if (_manufacturer.contains('huawei') || _manufacturer.contains('honor')) {
      return 'Huawei';
    }
    if (_manufacturer.contains('oppo') || _manufacturer.contains('realme')) {
      return 'Oppo / Realme';
    }
    if (_manufacturer.contains('vivo')) {
      return 'Vivo';
    }
    return _manufacturer.isNotEmpty ? _manufacturer.toUpperCase() : 'Android';
  }

  List<String> _getOemInstructions() {
    final mfr = _manufacturer.isNotEmpty ? _manufacturer : _brand;
    if (mfr.contains('tecno') ||
        mfr.contains('infinix') ||
        mfr.contains('itel') ||
        mfr.contains('transsion')) {
      return const [
        'افتح تطبيق إدارة الهاتف (Phone Master).',
        'اختر "إدارة التشغيل التلقائي" (Auto-start) وفعل NetGet.',
        'في "حماية البطارية"، اختر السماح للتشغيل في الخلفية بلا قيود.',
      ];
    }
    if (mfr.contains('xiaomi') ||
        mfr.contains('redmi') ||
        mfr.contains('poco')) {
      return const [
        'افتح تطبيق "الحماية" (Security) > الأذونات > التشغيل التلقائي (Autostart) وفعل NetGet.',
        'في توفير البطارية (Battery Saver)، اختر "لا توجد قيود" (No restrictions).',
      ];
    }
    if (mfr.contains('samsung')) {
      return const [
        'من إعدادات البطارية > حد الاستخدام في الخلفية.',
        'أضف NetGet إلى قائمة "التطبيقات التي لا يتم وضعها في السكون أبدًا" (Never sleeping apps).',
      ];
    }
    if (mfr.contains('huawei') || mfr.contains('honor')) {
      return const [
        'افتح إدارة الهاتف (Optimizer) > بدء تشغيل التطبيقات (App Launch).',
        'عطّل الإدارة التلقائية لـ NetGet، وفعّل "التشغيل في الخلفية".',
      ];
    }
    return const [
      'عطّل تحسين استهلاك البطارية لـ NetGet من القائمة أدناه.',
      'اسمح للتطبيق بالعمل في الخلفية لإكمال التحميلات حتى عند إغلاق الشاشة.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final oemName = _getOemDisplayName();
    final instructions = _getOemInstructions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('إبقاء التحميلات نشطة'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 36,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '«ما بنبدأ من الصفر»',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'بعض الهواتف توقف التحميلات فجأة لتوفير البطارية. خطوات بسيطة تضمن استمرار التحميل بأمان.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Device and Status Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'الجهاز: $oemName $_model',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isBatteryOptimizationIgnored
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isBatteryOptimizationIgnored
                                        ? Icons.check_circle
                                        : Icons.warning_amber,
                                    size: 16,
                                    color: _isBatteryOptimizationIgnored
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isBatteryOptimizationIgnored
                                        ? 'محمي'
                                        : 'غير محمي',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _isBatteryOptimizationIgnored
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _requestIgnoreBatteryOptimizations,
                          icon: const Icon(Icons.battery_charging_full),
                          label: Text(
                            _isBatteryOptimizationIgnored
                                ? 'تحسين البطارية معطّل بالفعل (ممتاز)'
                                : 'تعطيل تحسين البطارية لـ NetGet',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: _isBatteryOptimizationIgnored
                                ? Colors.green[700]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // OEM Instructions Section
                Text(
                  'خطوات حماية إضافية لـ $oemName:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...instructions.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _openOemBatterySettings,
                  icon: const Icon(Icons.settings_suggest_outlined),
                  label: Text('فتح إعدادات الجهاز ($oemName)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
            ),
    );
  }
}
