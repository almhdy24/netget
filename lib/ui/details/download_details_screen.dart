import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/segment_planner.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/download_status.dart';
import '../../models/download_task.dart';
import '../../services/analytics_service.dart';
import '../../services/download_manager.dart';
import 'segment_map_painter.dart';
import 'speed_graph_painter.dart';

/// Classic IDM-style download properties screen with dedicated tabs:
/// [General], [Segments], [Speed Graph], [Log].
class DownloadDetailsScreen extends StatefulWidget {
  final DownloadManager manager;
  final String taskId;
  final bool isPaneMode;

  const DownloadDetailsScreen({
    super.key,
    required this.manager,
    required this.taskId,
    this.isPaneMode = false,
  });

  @override
  State<DownloadDetailsScreen> createState() => _DownloadDetailsScreenState();
}

class _DownloadDetailsScreenState extends State<DownloadDetailsScreen>
    with SingleTickerProviderStateMixin {
  late Stream<TaskDetailsUpdate> _detailsStream;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    AnalyticsService.screenView('details');
    _detailsStream = widget.manager.watchTaskDetails(widget.taskId);
  }

  @override
  void didUpdateWidget(covariant DownloadDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _detailsStream = widget.manager.watchTaskDetails(widget.taskId);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

        final statusColor = _getStatusColor(context, task.status);

        final header = _buildHeader(context, task, statusColor);
        final tabBar = TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Segments'),
            Tab(text: 'Speed Graph'),
            Tab(text: 'Log'),
          ],
        );

        final body = Column(
          children: [
            header,
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
              ),
              child: tabBar,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(context, task, isDark),
                  _buildSegmentsTab(context, task, segments, isDark),
                  _buildSpeedTab(context, task, speedSamples, isDark),
                  _buildLogTab(context, eventLog, isDark),
                ],
              ),
            ),
          ],
        );

        if (widget.isPaneMode) {
          return body;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              NetGetUtils.middleEllipsis(task.fileName, maxLength: 28),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            actions: [
              if (task.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause),
                  tooltip: 'Pause',
                  onPressed: () => widget.manager.pauseDownload(task.id),
                )
              else if (task.status.isPaused || task.status.isFailed)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Resume',
                  onPressed: () => widget.manager.resumeDownload(task.id),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-download',
                onPressed: () => widget.manager.reDownload(task.id),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () async {
                  await widget.manager.deleteTask(task.id, deleteFile: false);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DownloadTask task,
    Color statusColor,
  ) {
    final theme = Theme.of(context);
    final progress = task.status.isCompleted
        ? 1.0
        : (task.totalBytes > 0 ? (task.progress ?? 0.0) : null);
    final percentage = task.progressPercentage ?? '--';

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  NetGetUtils.getFileTypeIcon(task.fileName),
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NetGetUtils.middleEllipsis(task.fileName, maxLength: 40),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _buildStatusBadge(task, statusColor),
                        const SizedBox(width: 8),
                        Text(
                          '${task.category.label} • Queue: ${task.queueName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: statusColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${NetGetUtils.formatBytes(task.downloadedBytes)} / '
                '${task.totalBytes > 0 ? NetGetUtils.formatBytes(task.totalBytes) : 'Unknown'} ($percentage)',
                style: NetGetUtils.tabularStyle(
                  theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
              if (task.status == DownloadStatus.downloading)
                Text(
                  '${NetGetUtils.formatSpeed(task.speedBytesPerSec)} • ETA ${NetGetUtils.formatEta(task.etaSeconds)}',
                  style: NetGetUtils.tabularStyle(
                    TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(DownloadTask task, Color color) {
    var label = task.status.label;
    if (task.status.isFailed &&
        (task.errorMessage?.contains('waiting for network') == true ||
            task.errorMessage?.contains('في انتظار الشبكة') == true)) {
      label = 'Waiting for network';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // --- GENERAL TAB ---
  Widget _buildGeneralTab(
    BuildContext context,
    DownloadTask task,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final avgSpeed = task.averageSpeedBytesPerSec > 0
        ? NetGetUtils.formatSpeed(task.averageSpeedBytesPerSec)
        : '--';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (task.status.isFailed &&
            task.errorMessage != null &&
            task.errorMessage!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.errorMessage!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => widget.manager.retryDownload(task.id),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(60, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Retry', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _buildInfoRow(
                context,
                label: 'URL',
                value: task.url,
                isCopyable: true,
                onCopy: () => _copyToClipboard(task.url, 'URL'),
              ),
              const Divider(height: 1),
              if (task.referrer != null && task.referrer!.isNotEmpty) ...[
                _buildInfoRow(
                  context,
                  label: 'Referrer',
                  value: task.referrer!,
                  isCopyable: true,
                  onCopy: () => _copyToClipboard(task.referrer!, 'Referrer'),
                ),
                const Divider(height: 1),
              ],
              _buildInfoRow(
                context,
                label: 'Save path',
                value: task.savePath,
                isCopyable: true,
                onCopy: () => _copyToClipboard(task.savePath, 'Save path'),
              ),
              const Divider(height: 1),
              _buildTwoColRow(
                'Resume support',
                task.resumable ? 'Yes (Byte range)' : 'No (Single stream)',
                'Connections',
                '${task.connectionCount} parts',
              ),
              const Divider(height: 1),
              _buildTwoColRow(
                'Elapsed time',
                NetGetUtils.formatElapsed(task.elapsedSeconds),
                'Average speed',
                avgSpeed,
              ),
              if (task.etag != null || task.lastModified != null) ...[
                const Divider(height: 1),
                _buildTwoColRow(
                  'ETag',
                  task.etag ?? '--',
                  'Last-Modified',
                  task.lastModified ?? '--',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTwoColRow(
    String label1,
    String val1,
    String label2,
    String val2,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildInfoItem(label1, val1)),
          Expanded(child: _buildInfoItem(label2, val2)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: NetGetUtils.tabularStyle(
            const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool isCopyable = false,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
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
              style: NetGetUtils.tabularStyle(const TextStyle(fontSize: 11)),
            ),
          ),
          if (isCopyable && onCopy != null)
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(3),
              child: const Padding(
                padding: EdgeInsetsDirectional.only(start: 6),
                child: Icon(Icons.copy, size: 14, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  // --- SEGMENTS TAB ---
  Widget _buildSegmentsTab(
    BuildContext context,
    DownloadTask task,
    List<DownloadSegment> segments,
    bool isDark,
  ) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'CONNECTION MAP (${task.connectionCount} SEGMENTS)',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
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
        Text(
          'SEGMENT DETAILS',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        'Conn',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Range (bytes)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Downloaded',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        'Status',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildSegmentRow(context, segments[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentRow(BuildContext context, DownloadSegment seg) {
    final totalSeg = seg.endByte > seg.startByte
        ? (seg.endByte - seg.startByte + 1)
        : 0;
    final pct = totalSeg > 0
        ? '${((seg.downloadedBytes / totalSeg) * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : '--';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#${seg.index + 1}',
              style: NetGetUtils.tabularStyle(
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '${NetGetUtils.formatBytes(seg.startByte)} - ${NetGetUtils.formatBytes(seg.endByte)}',
              style: NetGetUtils.tabularStyle(const TextStyle(fontSize: 10.5)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              NetGetUtils.formatBytes(seg.downloadedBytes),
              textAlign: TextAlign.end,
              style: NetGetUtils.tabularStyle(const TextStyle(fontSize: 10.5)),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              seg.isCompleted ? 'Done' : pct,
              textAlign: TextAlign.end,
              style: NetGetUtils.tabularStyle(
                TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: seg.isCompleted
                      ? const Color(0xFF15803D)
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SPEED GRAPH TAB ---
  Widget _buildSpeedTab(
    BuildContext context,
    DownloadTask task,
    List<double> speedSamples,
    bool isDark,
  ) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'LIVE TRANSFER SPEED (60 SECONDS)',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 140,
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
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Current Speed',
                NetGetUtils.formatSpeed(task.speedBytesPerSec),
                theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                context,
                'Average Speed',
                NetGetUtils.formatSpeed(task.averageSpeedBytesPerSec),
                theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: NetGetUtils.tabularStyle(
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- LOG TAB ---
  Widget _buildLogTab(
    BuildContext context,
    List<TaskLogEvent> eventLog,
    bool isDark,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: theme.colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOG ENTRIES (${eventLog.length}/200)',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.copy, size: 15),
                tooltip: 'Copy all log entries',
                onPressed: () {
                  final raw = eventLog
                      .map(
                        (e) =>
                            '[${e.timestamp.toIso8601String()}] [${e.level}] ${e.message}',
                      )
                      .join('\n');
                  _copyToClipboard(raw, 'Event log');
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: eventLog.isEmpty
              ? const Center(
                  child: Text(
                    'No events recorded yet',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: eventLog.length,
                  reverse: true,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final event = eventLog[eventLog.length - 1 - i];
                    final timeStr =
                        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';
                    final isErr = event.level == 'ERROR';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            timeStr,
                            style: NetGetUtils.tabularStyle(
                              const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isErr
                                  ? theme.colorScheme.error.withValues(
                                      alpha: 0.15,
                                    )
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              event.level,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isErr
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              event.message,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isErr
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
