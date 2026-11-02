import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils.dart';
import '../../models/download_status.dart';
import '../../models/download_task.dart';
import '../../services/download_manager.dart';

class DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final DownloadManager manager;

  const DownloadCard({
    super.key,
    required this.task,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final statusColor = _getStatusColor(task.status);
    final fileIcon = NetGetUtils.getFileTypeIcon(task.fileName);
    final uri = Uri.tryParse(task.url);
    final host = uri?.host ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: File Icon + File Name & Domain + Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(fileIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (host.isNotEmpty)
                        Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(task.status, statusColor, isDark),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            _buildProgressBar(context, statusColor),

            const SizedBox(height: 8),

            // Progress info & stats row
            _buildStatsRow(context),

            // Error message if failed
            if (task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 14, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.errorMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.error,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Action button bar
            _buildActionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DownloadStatus status, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, Color statusColor) {
    if (task.status.isCompleted) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: 1.0,
          backgroundColor: statusColor.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          minHeight: 6,
        ),
      );
    }

    if (task.status.isFailed || task.status.isCancelled) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: task.progress ?? 0.0,
          backgroundColor: statusColor.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          minHeight: 6,
        ),
      );
    }

    final progress = task.progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress, // null produces indeterminate animation when totalBytes is unknown
        backgroundColor: statusColor.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        minHeight: 6,
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final theme = Theme.of(context);
    final downloadedStr = NetGetUtils.formatBytes(task.downloadedBytes);
    final totalStr = task.totalBytes > 0
        ? NetGetUtils.formatBytes(task.totalBytes)
        : 'Unknown';

    final percentageStr = task.progressPercentage;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Downloaded vs Total
        Text(
          task.totalBytes > 0
              ? '$downloadedStr / $totalStr${percentageStr != null ? ' ($percentageStr)' : ''}'
              : downloadedStr,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),

        // Speed or ETA or status note
        if (task.status == DownloadStatus.downloading) ...[
          Row(
            children: [
              Text(
                NetGetUtils.formatSpeed(task.speedBytesPerSec),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
              if (task.etaSeconds != null) ...[
                const SizedBox(width: 6),
                Text(
                  '• ${NetGetUtils.formatEta(task.etaSeconds)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ] else if (task.status == DownloadStatus.completed) ...[
          Row(
            children: [
              Icon(Icons.check_rounded, size: 13, color: _getStatusColor(task.status)),
              const SizedBox(width: 2),
              Text(
                'Complete',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getStatusColor(task.status),
                ),
              ),
            ],
          ),
        ] else if (task.status == DownloadStatus.paused) ...[
          Text(
            task.resumable ? 'Resumable' : 'No-Resume',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: task.resumable
                  ? const Color(0xFFF57C00)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (task.status.isActive) ...[
          if (task.status == DownloadStatus.downloading)
            _buildIconButton(
              icon: Icons.pause_rounded,
              tooltip: 'Pause',
              color: const Color(0xFFF57C00),
              onPressed: () => manager.pauseDownload(task.id),
            ),
          _buildIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Cancel',
            color: Colors.grey,
            onPressed: () => manager.cancelDownload(task.id),
          ),
        ] else if (task.status.isPaused) ...[
          _buildIconButton(
            icon: Icons.play_arrow_rounded,
            tooltip: 'Resume',
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => manager.resumeDownload(task.id),
          ),
          _buildIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: Colors.grey,
            onPressed: () => _confirmDelete(context),
          ),
        ] else if (task.status.isFailed || task.status.isCancelled) ...[
          _buildIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Retry',
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => manager.retryDownload(task.id),
          ),
          _buildIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: Colors.grey,
            onPressed: () => _confirmDelete(context),
          ),
        ] else if (task.status.isCompleted) ...[
          _buildIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: 'Open File',
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => _openFile(context),
          ),
          _buildIconButton(
            icon: Icons.share_rounded,
            tooltip: 'Share',
            color: Theme.of(context).colorScheme.secondary,
            onPressed: () => _shareFile(context),
          ),
          _buildIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: Colors.grey,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    final file = File(task.savePath);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File does not exist on device.')),
        );
      }
      return;
    }

    try {
      final result = await OpenFilex.open(task.savePath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'No application found to open this file.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(BuildContext context) async {
    final file = File(task.savePath);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File does not exist to share.')),
        );
      }
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(task.savePath)],
          text: task.fileName,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share file: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    bool alsoDeleteFile = true;
    final fileExists = await File(task.savePath).exists();

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Delete Download'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remove "${task.fileName}" from NetGet?',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (fileExists) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: alsoDeleteFile,
                      title: const Text(
                        'Also delete file from storage',
                        style: TextStyle(fontSize: 13),
                      ),
                      onChanged: (val) {
                        setState(() => alsoDeleteFile = val ?? true);
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await manager.deleteTask(task.id, deleteFile: alsoDeleteFile && fileExists);
    }
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
        return const Color(0xFF1565C0);
      case DownloadStatus.paused:
        return const Color(0xFFF57C00);
      case DownloadStatus.completed:
        return const Color(0xFF2E7D32);
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return const Color(0xFFD32F2F);
    }
  }
}
