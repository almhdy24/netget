import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/download_status.dart';
import '../../services/analytics_service.dart';
import '../../services/download_manager.dart';

/// In-app Statistics and Telemetry Reports Screen.
/// Computes all metrics strictly from local task repository.
class StatisticsScreen extends StatefulWidget {
  final DownloadManager manager;

  const StatisticsScreen({super.key, required this.manager});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('statistics');
    AnalyticsService.trackStatsViewed(view: 'reports_screen');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    final tasks = widget.manager.tasks;

    final totalTasks = tasks.length;
    final completedTasks = tasks
        .where((t) => t.status == DownloadStatus.completed)
        .toList();
    final failedTasks = tasks
        .where((t) => t.status == DownloadStatus.failed)
        .toList();

    final totalDownloadedBytes = tasks.fold<int>(
      0,
      (sum, t) => sum + t.downloadedBytes,
    );

    final successRate = totalTasks > 0
        ? ((completedTasks.length / totalTasks) * 100).toStringAsFixed(1)
        : '0.0';

    // File type distribution
    final Map<DownloadCategory, int> categoryCounts = {};
    final Map<DownloadCategory, int> categoryBytes = {};
    for (final cat in DownloadCategory.values) {
      if (cat == DownloadCategory.all) continue;
      categoryCounts[cat] = 0;
      categoryBytes[cat] = 0;
    }

    for (final task in tasks) {
      final cat = NetGetUtils.classifyCategory(task.fileName);
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      categoryBytes[cat] = (categoryBytes[cat] ?? 0) + task.downloadedBytes;
    }

    // Daily activity for the past 7 days
    final now = DateTime.now();
    final List<_DayActivity> past7Days = List.generate(7, (i) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i));
      final count = tasks.where((t) {
        final d = t.createdAt;
        return d.year == day.year && d.month == day.month && d.day == day.day;
      }).length;
      return _DayActivity(date: day, count: count);
    });

    final maxDayCount = past7Days.fold<int>(
      1,
      (max, d) => d.count > max ? d.count : max,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'إحصائيات وتقارير التحميل' : 'Statistics & Reports',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI Metric Cards Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: isArabic
                      ? 'إجمالي البيانات المحملة'
                      : 'Total Data Transferred',
                  value: NetGetUtils.formatBytes(totalDownloadedBytes),
                  icon: Icons.data_usage_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: isArabic ? 'نسبة النجاح' : 'Success Rate',
                  value: '$successRate%',
                  icon: Icons.verified_rounded,
                  color: NetGetTheme.brandGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: isArabic
                      ? 'التحميلات المكتملة'
                      : 'Completed Downloads',
                  value: '${completedTasks.length} / $totalTasks',
                  icon: Icons.check_circle_outline_rounded,
                  color: NetGetTheme.brandCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: isArabic ? 'التحميلات الفاشلة' : 'Failed Tasks',
                  value: '${failedTasks.length}',
                  icon: Icons.error_outline_rounded,
                  color: failedTasks.isNotEmpty
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 7-Day Activity Chart Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF2E333B)
                    : const Color(0xFFE2E6EC),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_view_week_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? 'النشاط خلال آخر 7 أيام'
                            : 'Activity (Last 7 Days)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: past7Days.map((day) {
                        final fraction = maxDayCount > 0
                            ? (day.count / maxDayCount)
                            : 0.0;
                        final isToday =
                            day.date.day == now.day &&
                            day.date.month == now.month;
                        final dayLabel = _formatDayName(
                          day.date.weekday,
                          isArabic,
                        );

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (day.count > 0)
                                  Text(
                                    '${day.count}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isToday
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: (fraction * 70).clamp(4.0, 70.0),
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  dayLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isToday
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // File Type Breakdown Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF2E333B)
                    : const Color(0xFFE2E6EC),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.pie_chart_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? 'توزيع الملفات حسب النوع'
                            : 'File Type Breakdown',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...DownloadCategory.values
                      .where(
                        (cat) =>
                            cat != DownloadCategory.all &&
                            (categoryCounts[cat] ?? 0) > 0,
                      )
                      .map((cat) {
                        final count = categoryCounts[cat] ?? 0;
                        final bytes = categoryBytes[cat] ?? 0;
                        final pct = totalTasks > 0 ? (count / totalTasks) : 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    cat.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '$count (${(pct * 100).toStringAsFixed(1)}%) • ${NetGetUtils.formatBytes(bytes)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getCategoryColor(cat),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  if (totalTasks == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          isArabic
                              ? 'لا توجد تحميلات مسجلة بعد'
                              : 'No downloads recorded yet',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1E23) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2E333B) : const Color(0xFFE2E6EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: NetGetUtils.tabularStyle(
              theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(DownloadCategory category) {
    switch (category) {
      case DownloadCategory.video:
        return const Color(0xFF29B6F6);
      case DownloadCategory.audio:
        return const Color(0xFFAB47BC);
      case DownloadCategory.images:
        return const Color(0xFF26A69A);
      case DownloadCategory.documents:
        return const Color(0xFFFFA726);
      case DownloadCategory.archives:
        return const Color(0xFFEC407A);
      case DownloadCategory.apps:
        return const Color(0xFF66BB6A);
      default:
        return Colors.blueGrey;
    }
  }

  String _formatDayName(int weekday, bool isArabic) {
    if (isArabic) {
      switch (weekday) {
        case 1:
          return 'اثن';
        case 2:
          return 'ثلا';
        case 3:
          return 'أرب';
        case 4:
          return 'خمي';
        case 5:
          return 'جمع';
        case 6:
          return 'سبت';
        case 7:
        default:
          return 'أحد';
      }
    }
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
      default:
        return 'Sun';
    }
  }
}

class _DayActivity {
  final DateTime date;
  final int count;

  const _DayActivity({required this.date, required this.count});
}
