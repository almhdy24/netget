import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';
import 'widgets/add_download_sheet.dart';
import 'widgets/download_card.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/stats_summary_card.dart';

enum _FilterTab { all, active, completed }

class HomeScreen extends StatefulWidget {
  final DownloadManager manager;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const HomeScreen({
    super.key,
    required this.manager,
    required this.themeModeNotifier,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _FilterTab _selectedTab = _FilterTab.all;
  final TextEditingController _quickUrlController = TextEditingController();

  @override
  void dispose() {
    _quickUrlController.dispose();
    super.dispose();
  }

  Future<void> _quickStartDownload() async {
    final url = _quickUrlController.text.trim();
    if (url.isEmpty) return;

    try {
      await widget.manager.addDownload(url: url);
      _quickUrlController.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download started'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _pasteToQuickInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _quickUrlController.text = text;
    }
  }

  List<DownloadTask> _getFilteredTasks() {
    switch (_selectedTab) {
      case _FilterTab.all:
        return widget.manager.tasks;
      case _FilterTab.active:
        return widget.manager.tasks.where((t) => !t.status.isCompleted).toList();
      case _FilterTab.completed:
        return widget.manager.completedTasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final filteredTasks = _getFilteredTasks();
        final allCount = widget.manager.tasks.length;
        final activeCount =
            widget.manager.tasks.where((t) => !t.status.isCompleted).length;
        final completedCount = widget.manager.completedTasks.length;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      NetGetConstants.appName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'v1.0',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  NetGetConstants.appSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  widget.themeModeNotifier.value == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  size: 20,
                ),
                tooltip: 'Toggle Theme',
                onPressed: () {
                  widget.themeModeNotifier.value =
                      widget.themeModeNotifier.value == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'clear_completed') {
                    _confirmClearCompleted(context);
                  } else if (value == 'about') {
                    _showAboutDialog(context);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'clear_completed',
                    enabled: completedCount > 0,
                    child: const Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Clear Completed'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('About NetGet'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              // Re-check tasks
              setState(() {});
            },
            child: CustomScrollView(
              slivers: [
                // Quick URL Input Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quickUrlController,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _quickStartDownload(),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Paste download link...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              prefixIcon: const Icon(Icons.link_rounded, size: 18),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  size: 16,
                                ),
                                tooltip: 'Paste',
                                onPressed: _pasteToQuickInput,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _quickStartDownload,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Icon(Icons.download_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),

                // Monitor Summary Dashboard
                SliverToBoxAdapter(
                  child: StatsSummaryCard(manager: widget.manager),
                ),

                // Filter Tabs Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: SegmentedButton<_FilterTab>(
                      segments: [
                        ButtonSegment(
                          value: _FilterTab.all,
                          label: Text('All ($allCount)'),
                        ),
                        ButtonSegment(
                          value: _FilterTab.active,
                          label: Text('Active ($activeCount)'),
                        ),
                        ButtonSegment(
                          value: _FilterTab.completed,
                          label: Text('Done ($completedCount)'),
                        ),
                      ],
                      selected: {_selectedTab},
                      onSelectionChanged: (set) {
                        setState(() => _selectedTab = set.first);
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Download List or Empty State
                if (filteredTasks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final task = filteredTasks[index];
                          return DownloadCard(
                            key: ValueKey(task.id),
                            task: task,
                            manager: widget.manager,
                          );
                        },
                        childCount: filteredTasks.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => AddDownloadSheet.show(
              context,
              manager: widget.manager,
            ),
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Add Link'),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    switch (_selectedTab) {
      case _FilterTab.all:
        return EmptyStateView(
          icon: Icons.cloud_download_outlined,
          title: 'No Downloads Yet',
          message:
              'Paste a URL in the bar above or tap "Add Link" to start downloading files.',
          buttonText: 'Add New Download',
          onButtonPressed: () => AddDownloadSheet.show(
            context,
            manager: widget.manager,
          ),
        );
      case _FilterTab.active:
        return const EmptyStateView(
          icon: Icons.check_circle_outline_rounded,
          title: 'No Active Downloads',
          message: 'All downloads have completed, or no transfers are running.',
        );
      case _FilterTab.completed:
        return const EmptyStateView(
          icon: Icons.folder_open_outlined,
          title: 'No Completed Downloads',
          message: 'Finished downloads will appear here with 1-tap open and share.',
        );
    }
  }

  Future<void> _confirmClearCompleted(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Completed Downloads'),
        content: const Text(
          'Remove all finished downloads from the list? Your downloaded files will remain safely stored on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear List'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.manager.clearCompleted(deleteFiles: false);
    }
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: NetGetConstants.appName,
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
      ),
      children: const [
        Text(
          'NetGet is a lightweight, fast, and reliable Android download manager '
          'inspired by classic desktop tools. Features real-time speed monitoring, '
          'HTTP range pause & resume, zero ads, and clean Material 3 design.',
        ),
      ],
    );
  }
}
