import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../../services/download_manager.dart';

class StatsSummaryCard extends StatelessWidget {
  final DownloadManager manager;

  const StatsSummaryCard({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeCount = manager.activeTasks.length;
    final pausedCount = manager.pausedTasks.length;
    final completedCount = manager.completedTasks.length;
    final totalSpeed = manager.currentTotalSpeed;
    final totalDownloaded = manager.totalDownloadedBytes;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              if (totalSpeed > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    NetGetUtils.formatSpeed(totalSpeed),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
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
                    ? const Color(0xFF2E7D32)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              _buildDivider(isDark),
              _buildStatItem(
                context,
                label: 'Transferred',
                value: NetGetUtils.formatBytes(totalDownloaded),
                icon: Icons.data_usage_rounded,
                color: theme.colorScheme.secondary,
              ),
            ],
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDark ? const Color(0xFF2C3138) : const Color(0xFFECEFF2),
    );
  }
}
