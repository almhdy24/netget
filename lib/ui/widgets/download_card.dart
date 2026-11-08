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
      MaterialPageRoute<void>(
        builder: (_) =>
            DownloadDetailsScreen(manager: manager, taskId: task.id),
      ),
    );
  }

  void _showContextMenu(BuildContext context, [Offset? globalPosition]) {
    final overlay =
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
                Icon(Icons.open_in_new, size: 18),
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
                  task.status.isActive ? Icons.pause : Icons.play_arrow,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(task.status.isActive ? 'Pause' : 'Resume'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18),
              SizedBox(width: 10),
              Text('Open folder'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_link',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 10),
              Text('Copy link'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'refresh_link',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 10),
              Text('Refresh link'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'redownload',
          child: Row(
            children: [
              Icon(Icons.restart_alt, size: 18),
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
                Icon(Icons.share, size: 18),
                SizedBox(width: 10),
                Text('Share file'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'properties',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18),
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
              Icon(Icons.playlist_remove, size: 18),
              SizedBox(width: 10),
              Text('Remove from list'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete_file',
          child: Row(
            children: [
              Icon(
                Icons.delete_forever,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              Text(
                'Delete with file',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
              Icon(Icons.refresh, size: 20),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 22,
            ),
          ),
          child: content,
        );
      },
    );
  }

  // --- DENSE TABLE-LIKE LIST ROW ---
  Widget _buildDenseRow(BuildContext context, DownloadTask currentTask) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context, currentTask.status);
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
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Checkbox(
                  value: isSelected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) => onSelectChanged?.call(val ?? false),
                ),
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(fileIcon, color: statusColor, size: 18),
              ),

            // File Name + Progress mini-bar
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    NetGetUtils.middleEllipsis(
                      currentTask.fileName,
                      maxLength: 36,
                    ),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
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
            const SizedBox(width: 8),

            // Size / Total with tabular figures
            Expanded(
              flex: 3,
              child: Text(
                currentTask.totalBytes > 0
                    ? '${NetGetUtils.formatBytes(currentTask.downloadedBytes)}/${NetGetUtils.formatBytes(currentTask.totalBytes)}'
                    : NetGetUtils.formatBytes(currentTask.downloadedBytes),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NetGetUtils.tabularStyle(
                  theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Speed or Status
            Expanded(
              flex: 3,
              child: Text(
                currentTask.status == DownloadStatus.downloading
                    ? NetGetUtils.formatSpeed(currentTask.speedBytesPerSec)
                    : (currentTask.status.isCompleted
                          ? 'Done'
                          : currentTask.status.label),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NetGetUtils.tabularStyle(
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: currentTask.status == DownloadStatus.downloading
                        ? theme.colorScheme.primary
                        : statusColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Mini Action Button
            IconButton(
              icon: Icon(
                currentTask.status.isActive
                    ? Icons.pause
                    : (currentTask.status.isCompleted
                          ? Icons.folder_open
                          : Icons.play_arrow),
                size: 16,
                color: statusColor,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: currentTask.status.isActive
                  ? 'Pause'
                  : (currentTask.status.isCompleted ? 'Open' : 'Resume'),
              onPressed: () {
                if (currentTask.status.isActive) {
                  manager.pauseDownload(currentTask.id);
                } else if (currentTask.status.isCompleted) {
                  _openFile(context);
                } else {
                  manager.resumeDownload(currentTask.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- STANDARD CARD ROW (Clean desktop feel, radius 6dp max) ---
  Widget _buildCard(BuildContext context, DownloadTask currentTask) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context, currentTask.status);
    final fileIcon = NetGetUtils.getFileTypeIcon(currentTask.fileName);
    final uri = Uri.tryParse(currentTask.url);
    final host = uri?.host ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: File Icon + File Name & Domain + Status Badge & Action Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Checkbox(
                        value: isSelected,
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) => onSelectChanged?.call(val ?? false),
                      ),
                    ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(fileIcon, color: statusColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          NetGetUtils.middleEllipsis(
                            currentTask.fileName,
                            maxLength: 40,
                          ),
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (host.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            host,
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(currentTask, statusColor),
                  const SizedBox(width: 4),
                  _buildQuickActionButton(context, currentTask, statusColor),
                ],
              ),

              const SizedBox(height: 6),

              // Progress bar (3.5dp)
              _buildProgressBar(context, currentTask, statusColor),

              const SizedBox(height: 5),

              // Progress info & stats row
              _buildStatsRow(context, currentTask, statusColor),

              // Error message if failed
              if (currentTask.status.isFailed &&
                  currentTask.errorMessage != null &&
                  currentTask.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 13,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentTask.errorMessage!,
                          style: TextStyle(
                            fontSize: 10.5,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    DownloadTask currentTask,
    Color statusColor,
  ) {
    final IconData icon;
    final String tooltip;
    final VoidCallback onPressed;

    if (currentTask.status == DownloadStatus.downloading) {
      icon = Icons.pause;
      tooltip = 'Pause';
      onPressed = () => manager.pauseDownload(currentTask.id);
    } else if (currentTask.status == DownloadStatus.paused ||
        currentTask.status == DownloadStatus.queued) {
      icon = Icons.play_arrow;
      tooltip = 'Resume';
      onPressed = () => manager.resumeDownload(currentTask.id);
    } else if (currentTask.status.isFailed ||
        currentTask.status == DownloadStatus.cancelled) {
      icon = Icons.refresh;
      tooltip = 'Retry';
      onPressed = () => manager.retryDownload(currentTask.id);
    } else {
      icon = Icons.folder_open;
      tooltip = 'Open';
      onPressed = () => _openFile(context);
    }

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  Widget _buildStatusBadge(DownloadTask currentTask, Color color) {
    var label = currentTask.status.label;
    if (currentTask.status.isFailed &&
        (currentTask.errorMessage?.contains('waiting for network') == true ||
            currentTask.errorMessage?.contains('في انتظار الشبكة') == true)) {
      label = 'Waiting for network';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    DownloadTask currentTask,
    Color statusColor,
  ) {
    final progress = currentTask.status.isCompleted
        ? 1.0
        : (currentTask.status.isFailed || currentTask.status.isCancelled)
        ? (currentTask.progress ?? 0.0)
        : currentTask.progress;

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: statusColor.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        minHeight: 3.5,
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    DownloadTask currentTask,
    Color statusColor,
  ) {
    final theme = Theme.of(context);
    final downloadedStr = NetGetUtils.formatBytes(currentTask.downloadedBytes);
    final totalStr = currentTask.totalBytes > 0
        ? NetGetUtils.formatBytes(currentTask.totalBytes)
        : 'Unknown';

    final percentageStr = currentTask.progressPercentage;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            currentTask.totalBytes > 0
                ? '$downloadedStr / $totalStr${percentageStr != null ? ' ($percentageStr)' : ''}'
                : downloadedStr,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NetGetUtils.tabularStyle(
              theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (currentTask.status == DownloadStatus.downloading) ...[
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    NetGetUtils.formatSpeed(currentTask.speedBytesPerSec),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NetGetUtils.tabularStyle(
                      TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                if (currentTask.etaSeconds != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '• ${NetGetUtils.formatEta(currentTask.etaSeconds)}',
                    style: NetGetUtils.tabularStyle(
                      theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (currentTask.status == DownloadStatus.completed) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 12, color: statusColor),
              const SizedBox(width: 2),
              Text(
                'Complete',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ] else if (currentTask.status == DownloadStatus.paused) ...[
          Text(
            currentTask.resumable ? 'Resumable' : 'No-Resume',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              color: currentTask.resumable
                  ? statusColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
    var alsoDeleteFile = true;
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
                    'Remove "${task.fileName}" from NetGet?',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (fileExists) ...[
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: alsoDeleteFile,
                      title: const Text(
                        'Also delete file from storage',
                        style: TextStyle(fontSize: 12.5),
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

  Color _getStatusColor(BuildContext context, DownloadStatus status) {
    final colors = Theme.of(context).statusColors;
    switch (status) {
      case DownloadStatus.downloading:
        return colors.downloading;
      case DownloadStatus.paused:
        return colors.paused;
      case DownloadStatus.queued:
        return colors.queued;
      case DownloadStatus.completed:
        return colors.completed;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return colors.failed;
    }
  }
}
