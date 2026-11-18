import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../../data/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../models/data_budget.dart';
import '../../services/analytics_service.dart';
import '../../services/download_manager.dart';

/// Screen for managing monthly mobile data budget and free window night bundles.
class DataBudgetScreen extends StatefulWidget {
  final SettingsRepository settingsRepository;
  final DownloadManager? manager;

  const DataBudgetScreen({
    super.key,
    required this.settingsRepository,
    this.manager,
  });

  @override
  State<DataBudgetScreen> createState() => _DataBudgetScreenState();
}

class _DataBudgetScreenState extends State<DataBudgetScreen> {
  AppSettings _settings = const AppSettings();
  BudgetUsageSummary? _summary;
  bool _isLoading = true;

  final TextEditingController _budgetAmountController = TextEditingController();
  bool _isGb = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _budgetAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final settings = await widget.settingsRepository.loadSettings();
    BudgetUsageSummary? summary;
    if (widget.manager != null) {
      summary = await widget.manager!.budgetService.getSummary(
        settings: settings,
      );
    }

    if (mounted) {
      setState(() {
        _settings = settings;
        _summary = summary;
        _isLoading = false;

        final bytes = settings.monthlyBudgetBytes ?? 0;
        if (bytes <= 0) {
          _budgetAmountController.text = '';
        } else if (bytes % (1024 * 1024 * 1024) == 0) {
          _isGb = true;
          _budgetAmountController.text = (bytes ~/ (1024 * 1024 * 1024))
              .toString();
        } else {
          _isGb = false;
          _budgetAmountController.text = (bytes ~/ (1024 * 1024)).toString();
        }
      });
    }
  }

  Future<void> _updateSettings(AppSettings updated) async {
    setState(() => _settings = updated);
    await widget.settingsRepository.saveSettings(updated);
    widget.manager?.updateSettings(updated);

    if (widget.manager != null) {
      final summary = await widget.manager!.budgetService.getSummary(
        settings: updated,
      );
      if (mounted) setState(() => _summary = summary);
    }
  }

  void _onBudgetAmountChanged(String val) {
    final numVal = int.tryParse(val.trim()) ?? 0;
    if (numVal <= 0) {
      _updateSettings(_settings.copyWith(monthlyBudgetBytes: 0));
    } else {
      final factor = _isGb ? 1024 * 1024 * 1024 : 1024 * 1024;
      _updateSettings(_settings.copyWith(monthlyBudgetBytes: numVal * factor));
    }
  }

  void _onUnitChanged(bool isGb) {
    setState(() => _isGb = isGb);
    _onBudgetAmountChanged(_budgetAmountController.text);
  }

  Future<void> _showAddEditFreeWindowDialog([
    FreeWindow? windowToEdit,
    int? editIndex,
  ]) async {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final labelController = TextEditingController(
      text: windowToEdit?.label ?? (isArabic ? 'باقة الليل' : 'Night Bundle'),
    );
    TimeOfDay start =
        windowToEdit?.start ?? const TimeOfDay(hour: 2, minute: 0);
    TimeOfDay end = windowToEdit?.end ?? const TimeOfDay(hour: 6, minute: 0);
    final selectedDays = List<int>.from(
      windowToEdit?.daysOfWeek ?? const [1, 2, 3, 4, 5, 6, 7],
    );

    final result = await showDialog<FreeWindow>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                windowToEdit == null
                    ? (isArabic ? 'إضافة فترة مجانية جديدة' : 'Add Free Window')
                    : (isArabic ? 'تعديل الفترة المجانية' : 'Edit Free Window'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: isArabic
                            ? 'اسم الباقة / الفترة'
                            : 'Window Label',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(isArabic ? 'وقت البدء' : 'Start Time'),
                      trailing: TextButton(
                        child: Text(start.format(ctx)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: start,
                          );
                          if (picked != null) {
                            setDialogState(() => start = picked);
                          }
                        },
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(isArabic ? 'وقت الانتهاء' : 'End Time'),
                      trailing: TextButton(
                        child: Text(end.format(ctx)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: end,
                          );
                          if (picked != null) {
                            setDialogState(() => end = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        isArabic ? 'الأيام النشطة:' : 'Active Days:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: List.generate(7, (i) {
                        final dayNum = i + 1;
                        final dayNamesAr = [
                          'إثن',
                          'ثلا',
                          'أرب',
                          'خمي',
                          'جمع',
                          'سبت',
                          'أحد',
                        ];
                        final dayNamesEn = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        final isSelected = selectedDays.contains(dayNum);
                        return FilterChip(
                          selected: isSelected,
                          label: Text(isArabic ? dayNamesAr[i] : dayNamesEn[i]),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedDays.add(dayNum);
                              } else if (selectedDays.length > 1) {
                                selectedDays.remove(dayNum);
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final window = FreeWindow(
                      label: labelController.text.trim().isNotEmpty
                          ? labelController.text.trim()
                          : (isArabic ? 'ساعات مجانية' : 'Free Hours'),
                      start: start,
                      end: end,
                      daysOfWeek: selectedDays,
                    );
                    Navigator.of(ctx).pop(window);
                  },
                  child: Text(isArabic ? 'حفظ' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final currentList = List<FreeWindow>.from(_settings.freeWindows);
      if (editIndex != null && editIndex < currentList.length) {
        currentList[editIndex] = result;
      } else {
        currentList.add(result);
      }
      unawaited(_updateSettings(_settings.copyWith(freeWindows: currentList)));
      AnalyticsService.trackSettingChanged(
        settingName: 'free_windows_count',
        settingValue: '${currentList.length}',
      );
    }
  }

  void _removeFreeWindow(int index) {
    final currentList = List<FreeWindow>.from(_settings.freeWindows);
    if (index >= 0 && index < currentList.length) {
      currentList.removeAt(index);
      unawaited(_updateSettings(_settings.copyWith(freeWindows: currentList)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'الرصيد والساعات المجانية' : 'Data Budget & Free Windows',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Usage & Savings Card
                _buildUsageOverviewCard(context, colorScheme, isArabic),
                const SizedBox(height: 16),

                // Monthly Budget Settings Card
                _buildMonthlyBudgetCard(context, colorScheme, isArabic),
                const SizedBox(height: 16),

                // Free Windows List Card
                _buildFreeWindowsCard(context, colorScheme, isArabic),
                const SizedBox(height: 16),

                // Default Network Policy Card
                _buildDefaultPolicyCard(context, colorScheme, isArabic),
              ],
            ),
    );
  }

  Widget _buildUsageOverviewCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final summary = _summary;
    final budgetBytes = _settings.monthlyBudgetBytes ?? 0;
    final percent = summary != null ? summary.usagePercent * 100.0 : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.donut_large, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  isArabic
                      ? 'استهلاك الدورة الشهرية الحالية'
                      : 'Current Billing Cycle',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                if (summary != null)
                  Text(
                    isArabic
                        ? '${summary.daysRemainingInPeriod} يوم متبقي'
                        : '${summary.daysRemainingInPeriod} days left',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: budgetBytes > 0
                    ? (percent / 100.0).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 12,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent >= 100.0
                      ? colorScheme.error
                      : (percent >= _settings.warningThresholdPercent
                            ? Colors.orange
                            : colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  budgetBytes > 0
                      ? (isArabic
                            ? 'المستهلك: ${NetGetUtils.formatBytes(summary?.countedBytes ?? 0)} من ${NetGetUtils.formatBytes(budgetBytes)}'
                            : 'Used: ${NetGetUtils.formatBytes(summary?.countedBytes ?? 0)} of ${NetGetUtils.formatBytes(budgetBytes)}')
                      : (isArabic
                            ? 'المستهلك على الهاتف: ${NetGetUtils.formatBytes(summary?.countedBytes ?? 0)}'
                            : 'Mobile used: ${NetGetUtils.formatBytes(summary?.countedBytes ?? 0)}'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (budgetBytes > 0)
                  Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: percent >= 100.0
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            // Savings showcase
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(70),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.savings_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? '«وفّرت بيانات هاتف حقيقية»'
                              : 'Mobile Data Saved',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isArabic
                              ? 'تم تحميل ${NetGetUtils.formatBytes(summary?.freeBytes ?? 0)} عبر الساعات المجانية دون خصم من باقتك.'
                              : '${NetGetUtils.formatBytes(summary?.freeBytes ?? 0)} downloaded during free windows without cost.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyBudgetCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'إعدادات باقة الهاتف' : 'Monthly Data Budget Settings',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _budgetAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isArabic
                          ? 'سقف الباقة الشهرية'
                          : 'Monthly Budget Cap',
                      hintText: isArabic ? 'مثال: 5' : 'e.g. 5',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: _onBudgetAmountChanged,
                  ),
                ),
                const SizedBox(width: 8),
                ToggleButtons(
                  isSelected: [_isGb, !_isGb],
                  onPressed: (index) => _onUnitChanged(index == 0),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 40,
                  ),
                  children: const [Text('GB'), Text('MB')],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isArabic
                      ? 'يوم تجديد الباقة في الشهر:'
                      : 'Monthly Reset Day:',
                  style: const TextStyle(fontSize: 13),
                ),
                DropdownButton<int>(
                  value: _settings.budgetResetDay.clamp(1, 28),
                  items: List.generate(28, (i) => i + 1).map((day) {
                    return DropdownMenuItem<int>(
                      value: day,
                      child: Text(isArabic ? 'يوم $day' : 'Day $day'),
                    );
                  }).toList(),
                  onChanged: (day) {
                    if (day != null) {
                      _updateSettings(_settings.copyWith(budgetResetDay: day));
                    }
                  },
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                isArabic
                    ? 'إيقاف التحميل تلقائياً عند استهلاك الرصيد'
                    : 'Hard stop on mobile data when budget reached',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                isArabic
                    ? 'يمنع استهلاك الرصيد الإضافي أو الرصيد الأساسي للهاتف'
                    : 'Prevents unwanted charges or draining phone balance',
                style: const TextStyle(fontSize: 11),
              ),
              value: _settings.budgetHardStop,
              onChanged: (val) {
                _updateSettings(_settings.copyWith(budgetHardStop: val));
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isArabic ? 'تنبيه الاقتراب من السقف:' : 'Warning Threshold:',
                  style: const TextStyle(fontSize: 13),
                ),
                DropdownButton<int>(
                  value: _settings.warningThresholdPercent,
                  items: const [50, 70, 80, 90].map((p) {
                    return DropdownMenuItem<int>(value: p, child: Text('$p%'));
                  }).toList(),
                  onChanged: (p) {
                    if (p != null) {
                      _updateSettings(
                        _settings.copyWith(warningThresholdPercent: p),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreeWindowsCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic
                          ? 'الساعات المجانية الليلية'
                          : 'Free Windows (Night Bundles)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'باقات MTN/Zain الليلية أو ساعات التحميل المجاني'
                          : 'MTN / Zain night bundles or free provider hours',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _showAddEditFreeWindowDialog(),
                  tooltip: isArabic ? 'إضافة فترة مجانية' : 'Add Free Window',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_settings.freeWindows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    isArabic
                        ? 'لم يتم ضبط أي ساعات مجانية بعد. اضغط + لإضافة باقة ليلية.'
                        : 'No free windows configured yet. Tap + to add one.',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _settings.freeWindows.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (ctx, index) {
                  final window = _settings.freeWindows[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.nightlight_round,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      window.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${window.start.format(context)} - ${window.end.format(context)} (${window.daysOfWeek.length == 7 ? (isArabic ? 'يومياً' : 'Daily') : (isArabic ? '${window.daysOfWeek.length} أيام' : '${window.daysOfWeek.length} days')})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _showAddEditFreeWindowDialog(window, index),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: colorScheme.error,
                          ),
                          onPressed: () => _removeFreeWindow(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultPolicyCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic
                  ? 'سياسة الشبكة الافتراضية'
                  : 'Default Download Network Policy',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            // ignore: deprecated_member_use
            RadioListTile<NetworkPolicy>(
              contentPadding: EdgeInsets.zero,
              value: NetworkPolicy.anyNetwork,
              // ignore: deprecated_member_use
              groupValue: _settings.defaultNetworkPolicy,
              title: Text(
                isArabic
                    ? 'أي شبكة (واي-فاي أو بيانات الهاتف)'
                    : 'Any Network (Wi-Fi or Mobile Data)',
                style: const TextStyle(fontSize: 13),
              ),
              // ignore: deprecated_member_use
              onChanged: (val) {
                if (val != null) {
                  _updateSettings(
                    _settings.copyWith(defaultNetworkPolicy: val),
                  );
                }
              },
            ),
            // ignore: deprecated_member_use
            RadioListTile<NetworkPolicy>(
              contentPadding: EdgeInsets.zero,
              value: NetworkPolicy.wifiOnly,
              // ignore: deprecated_member_use
              groupValue: _settings.defaultNetworkPolicy,
              title: Text(
                isArabic
                    ? 'واي-فاي فقط (توقف عند التحول لبيانات الهاتف)'
                    : 'Wi-Fi Only (Pause on mobile data)',
                style: const TextStyle(fontSize: 13),
              ),
              // ignore: deprecated_member_use
              onChanged: (val) {
                if (val != null) {
                  _updateSettings(
                    _settings.copyWith(defaultNetworkPolicy: val),
                  );
                }
              },
            ),
            // ignore: deprecated_member_use
            RadioListTile<NetworkPolicy>(
              contentPadding: EdgeInsets.zero,
              value: NetworkPolicy.wifiOrFreeWindow,
              // ignore: deprecated_member_use
              groupValue: _settings.defaultNetworkPolicy,
              title: Text(
                isArabic
                    ? 'واي-فاي أو الساعات المجانية (الاستئناف التلقائي ليلاً)'
                    : 'Wi-Fi or Free Windows (Auto-resume at night)',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                isArabic
                    ? 'يستأنف تلقائياً في الساعات الليلية ويتوقف نهاراً للحفاظ على رصيدك'
                    : 'Resumes automatically in night windows and pauses by day',
                style: const TextStyle(fontSize: 11),
              ),
              // ignore: deprecated_member_use
              onChanged: (val) {
                if (val != null) {
                  _updateSettings(
                    _settings.copyWith(defaultNetworkPolicy: val),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
