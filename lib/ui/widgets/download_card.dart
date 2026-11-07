import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/download_status.dart';
import '../../models/download_task.dart';
import '../../services/download_manager.dart';
import '../details/download_details_screen.dart';

class DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final DownloadManager manager;
  final bool isDense;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onSelectChanged;

  const DownloadCard({
    super.key,
    required this.task,
    required this.manager,
    this.isDense = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onSelectChanged,
  });

  void _openDetails(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DownloadDetailsScreen(manager: manager, taskId: task.id),
      ),
    );
  }

  void _showContextMenu(BuildContext context, [Offset? globalPosition]) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position =
        globalPosition ??
        (context.findRenderObject() as RenderBox?)?.localToGlobal(
          Offset.zero,
        ) ??
        Offset.zero;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 40, 40),
        Offset.zero & (overlay?.size ?? const Size(800, 1200)),
      ),
      items: [
        if (task.status.isCompleted)
          const PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 18),
                SizedBox(width: 10),
                Text('Open'),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: task.status.isActive ? 'pause' : 'resume',
            child: Row(
              children: [
                Icon(
                  task.status.isActive
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                ),
                SizedBox(width: 10),
                Text(task.status.isActive ? 'Pause' : 'Resume'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 18),
              SizedBox(width: 10),
              Text('Open folder'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_link',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 10),
              Text('Copy link'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'refresh_link',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 18),
              SizedBox(width: 10),
              Text('Refresh link'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'redownload',
          child: Row(
            children: [
              Icon(Icons.restart_alt_rounded, size: 18),
              SizedBox(width: 10),
              Text('Re-download'),
            ],
          ),
        ),
        if (task.status.isCompleted)
          const PopupMenuItem(
            value: 'share',
            child: Row(
              children: [
                Icon(Icons.share_rounded, size: 18),
                SizedBox(width: 10),
                Text('Share file'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'properties',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('Properties'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'remove_list',
          child: Row(
            children: [
              Icon(
                Icons.playlist_remove_rounded,
                size: 18,
                color: Colors.orange,
              ),
              SizedBox(width: 10),
              Text('Remove from list'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete_file',
          child: Row(
            children: [
              Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text('Delete with file', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((choice) {
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case 'open':
          _openFile(context);
          break;
        case 'pause':
          manager.pauseDownload(task.id);
          break;
        case 'resume':
          manager.resumeDownload(task.id);
          break;
        case 'open_folder':
          _openFolder(context);
          break;
        case 'copy_link':
          _copyLink(context);
          break;
        case 'refresh_link':
          _showRefreshLinkDialog(context);
          break;
        case 'redownload':
          manager.reDownload(task.id);
          break;
        case 'share':
          _shareFile(context);
          break;
        case 'properties':
          _openDetails(context);
          break;
        case 'remove_list':
          manager.deleteTask(task.id, deleteFile: false);
          break;
        case 'delete_file':
          manager.deleteTask(task.id, deleteFile: true);
          break;
      }
    });
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: task.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openFolder(BuildContext context) async {
    final parentDir = File(task.savePath).parent.path;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Folder: $parentDir'),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: parentDir)),
        ),
      ),
    );
  }

  Future<void> _showRefreshLinkDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.refresh_rounded, size: 20),
              SizedBox(width: 8),
              Text('Refresh Download Link'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter updated URL for "${task.fileName}".\nNetGet will verify file size and resume seamlessly.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New URL',
                  hintText: 'https://...',
                  errorText: errorMsg,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isEmpty) return;
                try {
                  await manager.refreshTaskUrl(task.id, url);
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link refreshed successfully'),
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(() {
                    errorMsg = e.toString().replaceFirst('Exception: ', '');
                  });
                }
              },
              child: const Text('Verify & Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DownloadTask>(
      valueListenable: manager.getTaskNotifier(task.id),
      builder: (context, currentTask, _) {
        final content = isDense
            ? _buildDenseRow(context, currentTask)
            : _buildCard(context, currentTask);

        return Dismissible(
          key: ValueKey('dismiss_${currentTask.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDelete(context),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          child: content,
        );
      },
    );
  }

  // --- DENSE TABLE-LIKE LIST ROW (48 dp minimum touch target) ---
  Widget _buildDenseRow(BuildContext context, DownloadTask currentTask) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _getStatusColor(currentTask.status);
    final fileIcon = NetGetUtils.getFileTypeIcon(currentTask.fileName);

    final progressVal = currentTask.status.isCompleted
        ? 1.0
        : (currentTask.totalBytes > 0 ? (currentTask.progress ?? 0.0) : null);

    return InkWell(
      onTap: () {
        if (isSelectionMode) {
          onSelectChanged?.call(!isSelected);
        } else {
          _openDetails(context);
        }
      },
      onLongPress: () => _showContextMenu(context),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF232830) : const Color(0xFFEAEDF2),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Checkbox(
                  value: isSelected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) => onSelectChanged?.call(val ?? false),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(fileIcon, color: statusColor, size: 20),
              ),

            // File Name + Progress mini-bar
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    task.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progressVal,
                      minHeight: 3,
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Size / Total with tabular figures
            Expanded(
              flex: 3,
              child: Text(
                task.totalBytes > 0
                    ? '${NetGetUtils.formatBytes(task.downloadedBytes)}/${NetGetUtils.formatBytes(task.totalBytes)}'
                    : NetGetUtils.formatBytes(task.downloadedBytes),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NetGetUtils.tabularStyle(
                  theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Speed or ETA
            Expanded(
              flex: 3,
              child: Text(
                task.status == DownloadStatus.downloading
                    ? NetGetUtils.formatSpeed(task.speedBytesPerSec)
                    : (task.status.isCompleted ? 'Done' : task.status.label),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NetGetUtils.tabularStyle(
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: task.status == DownloadStatus.downloading
                        ? theme.colorScheme.primary
                        : statusColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Mini Action Button
            IconButton(
              icon: Icon(
                task.status.isActive
                    ? Icons.pause_rounded
                    : (task.status.isCompleted
                          ? Icons.folder_open_rounded
                          : Icons.play_arrow_rounded),
                size: 18,
                color: statusColor,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: task.status.isActive
                  ? 'Pause'
                  : (task.status.isCompleted ? 'Open' : 'Resume'),
              onPressed: () {
                if (task.status.isActive) {
                  manager.pauseDownload(task.id);
                } else if (task.status.isCompleted) {
                  _openFile(context);
                } else {
                  manager.resumeDownload(task.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- STANDARD CARD VIEW ---
  Widget _buildCard(BuildContext context, DownloadTask currentTask) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final statusColor = _getStatusColor(currentTask.status);
    final fileIcon = NetGetUtils.getFileTypeIcon(currentTask.fileName);
    final uri = Uri.tryParse(currentTask.url);
    final host = uri?.host ?? '';

    return Card(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF2C3138) : const Color(0xFFE2E4E8)),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isSelectionMode) {
            onSelectChanged?.call(!isSelected);
          } else {
            _openDetails(context);
          }
        },
        onLongPress: () => _showContextMenu(context),
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: File Icon + File Name & Domain + Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (val) => onSelectChanged?.call(val ?? false),
                      ),
                    ),
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
                          currentTask.fileName,
                          maxLines: 2,
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
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
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
              if (task.status.isFailed &&
                  task.errorMessage != null &&
                  task.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
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

              // Action button bar (single primary action)
              _buildActionBar(context, currentTask),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DownloadStatus status, Color color, bool isDark) {
    String label = status.label;
    if (task.status.isFailed &&
        (task.errorMessage?.contains('waiting for network') == true ||
            task.errorMessage?.contains('في انتظار الشبكة') == true)) {
      label = 'Waiting for network';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
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
        value: progress,
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
        Flexible(
          child: Text(
            task.totalBytes > 0
                ? '$downloadedStr / $totalStr${percentageStr != null ? ' ($percentageStr)' : ''}'
                : downloadedStr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NetGetUtils.tabularStyle(
              theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (task.status == DownloadStatus.downloading) ...[
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    NetGetUtils.formatSpeed(task.speedBytesPerSec),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NetGetUtils.tabularStyle(
                      TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                if (task.etaSeconds != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '• ${NetGetUtils.formatEta(task.etaSeconds)}',
                    style: NetGetUtils.tabularStyle(
                      theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (task.status == DownloadStatus.completed) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                size: 13,
                color: _getStatusColor(task.status),
              ),
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

  Widget _buildActionBar(BuildContext context, DownloadTask currentTask) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (currentTask.status == DownloadStatus.downloading)
          FilledButton.tonalIcon(
            onPressed: () => manager.pauseDownload(currentTask.id),
            icon: const Icon(Icons.pause_rounded, size: 16),
            label: const Text('Pause'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
          )
        else if (currentTask.status == DownloadStatus.paused ||
            currentTask.status == DownloadStatus.queued)
          FilledButton.tonalIcon(
            onPressed: () => manager.resumeDownload(currentTask.id),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Resume'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
          )
        else if (currentTask.status.isFailed ||
            currentTask.status == DownloadStatus.cancelled)
          FilledButton.tonalIcon(
            onPressed: () => manager.retryDownload(currentTask.id),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
          )
        else if (currentTask.status.isCompleted)
          FilledButton.tonalIcon(
            onPressed: () => _openFile(context),
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: const Text('Open'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
          ),
      ],
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
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
        ShareParams(files: [XFile(task.savePath)], text: task.fileName),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share file: $e')));
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    bool alsoDeleteFile = true;
    final fileExists = await File(task.savePath).exists();

    if (!context.mounted) return false;

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
                    'Remove "${task.fileName}" from NDM?',
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
      await manager.deleteTask(
        task.id,
        deleteFile: alsoDeleteFile && fileExists,
      );
      return true;
    }
    return false;
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.queued:
        return NetGetTheme.brandBlue;
      case DownloadStatus.downloading:
        return NetGetTheme.brandCyan;
      case DownloadStatus.paused:
        return NetGetTheme.warningAmber;
      case DownloadStatus.completed:
        return NetGetTheme.brandGreen;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return NetGetTheme.errorRed;
    }
  }
}
