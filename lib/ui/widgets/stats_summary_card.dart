import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/analytics_service.dart';
import '../../services/download_manager.dart';
import '../reports/statistics_screen.dart';

class StatsSummaryCard extends StatelessWidget {
  final DownloadManager manager;
  final bool isDense;
  final VoidCallback onToggleDense;
  final VoidCallback onAddLink;
  final VoidCallback? onDeleteSelected;
  final bool isSelectionMode;

  const StatsSummaryCard({
    super.key,
    required this.manager,
    required this.isDense,
    required this.onToggleDense,
    required this.onAddLink,
    this.onDeleteSelected,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeCount = manager.activeTasks.length;
    final pausedCount = manager.pausedTasks.length;
    final completedCount = manager.completedTasks.length;
    final queuedCount = manager.queuedCount;
    final completedToday = manager.completedTodayCount;
    final totalSpeed = manager.currentTotalSpeed;
    final currentMode = manager.speedMode;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
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
          // Header Row: Transfer Monitor + Speed badge + Speed Mode Dropdown
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  AnalyticsService.trackStatsViewed(view: 'summary_card_header');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StatisticsScreen(manager: manager),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 18,
                      color: totalSpeed > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Transfer Monitor',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.insights_rounded,
                      size: 14,
                      color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (totalSpeed > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    NetGetUtils.formatSpeed(totalSpeed),
                    style: NetGetUtils.tabularStyle(
                      TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<SpeedMode>(
                  value: currentMode,
                  isDense: true,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  items: SpeedMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(
                        mode.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode != null) {
                      manager.setSpeedMode(mode);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Stat items row (scrollable horizontally if constrained)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatItem(
                  context,
                  label: 'Active',
                  value: '$activeCount',
                  icon: Icons.downloading_rounded,
                  color: activeCount > 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                _buildDivider(isDark),
                _buildStatItem(
                  context,
                  label: 'Paused',
                  value: '$pausedCount',
                  icon: Icons.pause_circle_outline_rounded,
                  color: pausedCount > 0
                      ? const Color(0xFFF57C00)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                _buildDivider(isDark),
                _buildStatItem(
                  context,
                  label: 'Done',
                  value: '$completedCount',
                  icon: Icons.check_circle_outline_rounded,
                  color: completedCount > 0
                      ? NetGetTheme.brandGreen
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                _buildDivider(isDark),
                _buildStatItem(
                  context,
                  label: 'Queued',
                  value: '$queuedCount',
                  icon: Icons.hourglass_empty_rounded,
                  color: queuedCount > 0
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                _buildDivider(isDark),
                _buildStatItem(
                  context,
                  label: 'Today',
                  value: '$completedToday',
                  icon: Icons.today_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
          ),
          const Divider(height: 14),

          // Desktop Toolbar Actions (scrollable horizontally if constrained)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolbarButton(
                  icon: Icons.add_link_rounded,
                  label: 'Add',
                  onPressed: onAddLink,
                  isPrimary: true,
                  theme: theme,
                ),
                const SizedBox(width: 6),
                _buildToolbarButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Resume all',
                  onPressed:
                      manager.pausedTasks.isNotEmpty ||
                          manager.failedTasks.isNotEmpty
                      ? () => manager.resumeAll()
                      : null,
                  theme: theme,
                ),
                const SizedBox(width: 6),
                _buildToolbarButton(
                  icon: Icons.pause_rounded,
                  label: 'Pause all',
                  onPressed: manager.activeTasks.isNotEmpty
                      ? () => manager.pauseAll()
                      : null,
                  theme: theme,
                ),
                const SizedBox(width: 6),
                _buildToolbarButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  onPressed: onDeleteSelected,
                  theme: theme,
                ),
                const SizedBox(width: 6),
                _buildToolbarButton(
                  icon: Icons.insights_rounded,
                  label: 'Stats',
                  onPressed: () {
                    AnalyticsService.trackStatsViewed(view: 'summary_card_toolbar');
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StatisticsScreen(manager: manager),
                      ),
                    );
                  },
                  theme: theme,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    isDense
                        ? Icons.view_agenda_outlined
                        : Icons.table_rows_outlined,
                    size: 19,
                  ),
                  tooltip: isDense
                      ? 'Switch to Card view'
                      : 'Switch to Compact Table view',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleDense,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: NetGetUtils.tabularStyle(
              theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? const Color(0xFF2C3138) : const Color(0xFFECEFF2),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required ThemeData theme,
    bool isPrimary = false,
  }) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
