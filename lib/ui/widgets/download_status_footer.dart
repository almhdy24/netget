import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/analytics_service.dart';
import '../../services/download_manager.dart';
import '../reports/statistics_screen.dart';

/// Compact desktop-style status footer (IDM / FDM status bar).
/// Shows active/queued counts, total transfer speed, and free disk space.
class DownloadStatusFooter extends StatefulWidget {
  final DownloadManager manager;

  const DownloadStatusFooter({super.key, required this.manager});

  @override
  State<DownloadStatusFooter> createState() => _DownloadStatusFooterState();
}

class _DownloadStatusFooterState extends State<DownloadStatusFooter> {
  int? _freeDiskBytes;
  Timer? _diskSpaceTimer;

  @override
  void initState() {
    super.initState();
    _checkDiskSpace();
    // Refresh free space every 30 seconds
    _diskSpaceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDiskSpace(),
    );
  }

  @override
  void dispose() {
    _diskSpaceTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkDiskSpace() async {
    try {
      final dir = await NetGetConstants.getDownloadsDirectory();
      final free = await NetGetUtils.getFreeDiskSpace(dir.path);
      if (mounted) {
        setState(() => _freeDiskBytes = free);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.statusColors;

    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final activeCount = widget.manager.activeTasks.length;
        final queuedCount = widget.manager.queuedCount;
        final totalSpeed = widget.manager.currentTotalSpeed;
        final isDownloading = totalSpeed > 0;

        return Container(
          height: 30,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
            ),
          ),
          child: Row(
            children: [
              // Active count indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDownloading
                          ? statusColors.downloading
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Active: $activeCount',
                    style: NetGetUtils.tabularStyle(
                      theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 10),
              _buildDivider(colorScheme),
              const SizedBox(width: 10),

              // Queued count
              Text(
                'Queued: $queuedCount',
                style: NetGetUtils.tabularStyle(
                  theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              const SizedBox(width: 10),
              _buildDivider(colorScheme),
              const SizedBox(width: 10),

              // Total Speed
              Flexible(
                child: Text(
                  isDownloading ? NetGetUtils.formatSpeed(totalSpeed) : 'Idle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NetGetUtils.tabularStyle(
                    TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDownloading
                          ? theme.colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Free Disk Space
              if (_freeDiskBytes != null) ...[
                Text(
                  'Free: ${NetGetUtils.formatBytes(_freeDiskBytes!)}',
                  style: NetGetUtils.tabularStyle(
                    theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildDivider(colorScheme),
                const SizedBox(width: 4),
              ],

              // Reports button
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: const Icon(Icons.bar_chart_outlined, size: 16),
                tooltip: 'Statistics & Reports',
                onPressed: () {
                  AnalyticsService.trackStatsViewed(view: 'status_footer');
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StatisticsScreen(manager: widget.manager),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(width: 1, height: 12, color: colorScheme.outlineVariant);
  }
}
