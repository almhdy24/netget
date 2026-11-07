import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/download_status.dart';
import '../../models/download_task.dart';
import '../../services/download_manager.dart';
import 'segment_map_painter.dart';
import 'speed_graph_painter.dart';

class DownloadDetailsScreen extends StatefulWidget {
  final DownloadManager manager;
  final String taskId;
  final bool isPaneMode; // True when rendered inside wide-screen side pane

  const DownloadDetailsScreen({
    super.key,
    required this.manager,
    required this.taskId,
    this.isPaneMode = false,
  });

  @override
  State<DownloadDetailsScreen> createState() => _DownloadDetailsScreenState();
}

class _DownloadDetailsScreenState extends State<DownloadDetailsScreen> {
  late Stream<TaskDetailsUpdate> _detailsStream;

  @override
  void initState() {
    super.initState();
    _detailsStream = widget.manager.watchTaskDetails(widget.taskId);
  }

  @override
  void didUpdateWidget(covariant DownloadDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _detailsStream = widget.manager.watchTaskDetails(widget.taskId);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<TaskDetailsUpdate>(
      stream: _detailsStream,
      builder: (context, snapshot) {
        // Fallback to finding task in manager list if stream has not emitted yet
        DownloadTask task;
        if (snapshot.hasData) {
          task = snapshot.data!.task;
        } else {
          final found = widget.manager.tasks.where(
            (t) => t.id == widget.taskId,
          );
          if (found.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Download not found')),
            );
          }
          task = found.first;
        }

        final segments = snapshot.data?.segments ?? task.segments;
        final speedSamples =
            snapshot.data?.speedSamples ??
            widget.manager.getSpeedSamples(widget.taskId);
        final eventLog =
            snapshot.data?.eventLog ??
            widget.manager.getTaskLogs(widget.taskId);

        final statusColor = _getStatusColor(task.status);
        final progress = task.progress ?? 0.0;
        final percentage = task.progressPercentage ?? '--';

        final bottomNavPadding =
            widget.isPaneMode ? 0.0 : MediaQuery.paddingOf(context).bottom;
        final content = SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomNavPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B1E23) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C323B)
                        : const Color(0xFFE2E6EC),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            NetGetUtils.getFileTypeIcon(task.fileName),
                            color: statusColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.fileName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildBadge(
                                    (task.status.isFailed &&
                                            (task.errorMessage?.contains('waiting for network') == true ||
                                                task.errorMessage?.contains('في انتظار الشبكة') == true))
                                        ? 'Waiting for network'
                                        : task.status.label,
                                    statusColor,
                                    isDark,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${task.category.label} • Queue: ${task.queueName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.status.isCompleted
                            ? 1.0
                            : (task.totalBytes > 0 ? progress : null),
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Stats row with tabular figures
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${NetGetUtils.formatBytes(task.downloadedBytes)} / '
                            '${task.totalBytes > 0 ? NetGetUtils.formatBytes(task.totalBytes) : 'Unknown'} ($percentage)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NetGetUtils.tabularStyle(
                              theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (task.status == DownloadStatus.downloading) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${NetGetUtils.formatSpeed(task.speedBytesPerSec)} • ETA ${NetGetUtils.formatEta(task.etaSeconds)}',
                            style: NetGetUtils.tabularStyle(
                              TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (task.status.isFailed &&
                        task.errorMessage != null &&
                        task.errorMessage!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: theme.colorScheme.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task.errorMessage!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  widget.manager.retryDownload(task.id),
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text('Retry'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Segment Map Section
              _buildSectionTitle(
                'Connection Segment Map (${task.connectionCount} parts)',
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                width: double.infinity,
                child: CustomPaint(
                  painter: SegmentMapPainter(
                    segments: segments,
                    totalBytes: task.totalBytes,
                    isCompleted: task.status.isCompleted,
                    isDark: isDark,
                    primaryColor: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Live Speed Sparkline Graph
              _buildSectionTitle('Live Speed Graph (60s history)'),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                width: double.infinity,
                child: CustomPaint(
                  painter: SpeedGraphPainter(
                    samples: speedSamples,
                    isDark: isDark,
                    primaryColor: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Information Grid
              _buildSectionTitle('Transfer Properties'),
              const SizedBox(height: 8),
              _buildInfoGrid(context, task, isDark),
              const SizedBox(height: 16),

              // Event Log Ring Buffer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildSectionTitle('Event Log (${eventLog.length}/200)'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final raw = eventLog
                          .map(
                            (e) =>
                                '[${e.timestamp.toIso8601String()}] [${e.level}] ${e.message}',
                          )
                          .join('\n');
                      _copyToClipboard(raw, 'Event log');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text(
                      'Copy Log',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 140,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF131518)
                      : const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF262A32)
                        : const Color(0xFFDEE2E8),
                  ),
                ),
                child: eventLog.isEmpty
                    ? const Center(
                        child: Text(
                          'No events recorded yet',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: eventLog.length,
                        reverse: true, // Show newest at top/bottom conveniently
                        itemBuilder: (ctx, i) {
                          final event = eventLog[eventLog.length - 1 - i];
                          final timeStr =
                              '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';
                          final isErr = event.level == 'ERROR';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '[$timeStr] [${event.level}] ${event.message}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: isErr
                                    ? Colors.redAccent
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );

        if (widget.isPaneMode) {
          return content;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(task.fileName, style: const TextStyle(fontSize: 16)),
            actions: [
              if (task.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause_rounded),
                  tooltip: 'Pause',
                  onPressed: () => widget.manager.pauseDownload(task.id),
                )
              else if (task.status.isPaused || task.status.isFailed)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: 'Resume',
                  onPressed: () => widget.manager.resumeDownload(task.id),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Re-download',
                onPressed: () => widget.manager.reDownload(task.id),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete',
                onPressed: () async {
                  await widget.manager.deleteTask(task.id, deleteFile: false);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: content,
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoGrid(BuildContext context, DownloadTask task, bool isDark) {
    final avgSpeed = task.averageSpeedBytesPerSec > 0
        ? NetGetUtils.formatSpeed(task.averageSpeedBytesPerSec)
        : '--';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1E23) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF2C323B) : const Color(0xFFE2E6EC),
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            context,
            label: 'Download URL',
            value: task.url,
            isCopyable: true,
            onCopy: () => _copyToClipboard(task.url, 'URL'),
          ),
          const Divider(height: 14),
          if (task.referrer != null && task.referrer!.isNotEmpty) ...[
            _buildInfoRow(
              context,
              label: 'Referrer',
              value: task.referrer!,
              isCopyable: true,
              onCopy: () => _copyToClipboard(task.referrer!, 'Referrer'),
            ),
            const Divider(height: 14),
          ],
          _buildInfoRow(
            context,
            label: 'Save Path',
            value: task.savePath,
            isCopyable: true,
            onCopy: () => _copyToClipboard(task.savePath, 'Save path'),
          ),
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  'Resume Support',
                  task.resumable ? 'Supported (Range)' : 'Single stream only',
                ),
              ),
              Expanded(
                child: _buildInfoItem(
                  'Connections',
                  '${task.connectionCount} parts',
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  'Elapsed Time',
                  NetGetUtils.formatElapsed(task.elapsedSeconds),
                ),
              ),
              Expanded(child: _buildInfoItem('Average Speed', avgSpeed)),
            ],
          ),
          if (task.etag != null || task.lastModified != null) ...[
            const Divider(height: 14),
            Row(
              children: [
                if (task.etag != null)
                  Expanded(child: _buildInfoItem('ETag', task.etag!)),
                if (task.lastModified != null)
                  Expanded(
                    child: _buildInfoItem('Last-Modified', task.lastModified!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool isCopyable = false,
    VoidCallback? onCopy,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        if (isCopyable && onCopy != null)
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
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
