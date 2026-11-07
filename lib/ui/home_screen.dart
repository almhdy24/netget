import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';
import 'details/download_details_screen.dart';
import 'shortcuts/app_shortcuts.dart';
import 'widgets/add_download_sheet.dart';
import 'widgets/download_card.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/stats_summary_card.dart';

enum _FilterTab { all, active, completed, queued, paused, failed }

enum _SortOption { dateDesc, dateAsc, nameAsc, sizeDesc, speedDesc }

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
  DownloadCategory _selectedCategory = DownloadCategory.all;
  _SortOption _sortOption = _SortOption.dateDesc;
  bool _isDense = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quickUrlController = TextEditingController();

  // Multi-selection state
  final Set<String> _selectedTaskIds = {};
  bool get _isSelectionMode => _selectedTaskIds.isNotEmpty;

  // Selected task ID for wide-screen detail pane
  String? _selectedTaskId;

  @override
  void dispose() {
    _searchController.dispose();
    _quickUrlController.dispose();
    super.dispose();
  }

  void _showAddSheet({String? initialUrl}) {
    AddDownloadSheet.show(
      context,
      manager: widget.manager,
      initialUrl: initialUrl,
      onOpenExisting: (task) {
        setState(() {
          _selectedTaskId = task.id;
        });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DownloadDetailsScreen(manager: widget.manager, taskId: task.id),
          ),
        );
      },
    );
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
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
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
    var list = List<DownloadTask>.from(widget.manager.tasks);

    // Filter by status tab
    switch (_selectedTab) {
      case _FilterTab.all:
        break;
      case _FilterTab.active:
        list = list.where((t) => !t.status.isCompleted).toList();
        break;
      case _FilterTab.completed:
        list = list.where((t) => t.status.isCompleted).toList();
        break;
      case _FilterTab.queued:
        list = list.where((t) => t.status == DownloadStatus.queued).toList();
        break;
      case _FilterTab.paused:
        list = list.where((t) => t.status == DownloadStatus.paused).toList();
        break;
      case _FilterTab.failed:
        list = list
            .where(
              (t) =>
                  t.status == DownloadStatus.failed ||
                  t.status == DownloadStatus.cancelled,
            )
            .toList();
        break;
    }

    // Filter by category
    if (_selectedCategory != DownloadCategory.all) {
      list = list.where((t) => t.category == _selectedCategory).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        return t.fileName.toLowerCase().contains(q) ||
            t.url.toLowerCase().contains(q);
      }).toList();
    }

    // Sort safely on cloned list
    switch (_sortOption) {
      case _SortOption.dateDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortOption.dateAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _SortOption.nameAsc:
        list.sort(
          (a, b) =>
              a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
        break;
      case _SortOption.sizeDesc:
        list.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
        break;
      case _SortOption.speedDesc:
        list.sort((a, b) => b.speedBytesPerSec.compareTo(a.speedBytesPerSec));
        break;
    }

    return list;
  }

  void _toggleSelectAll(List<DownloadTask> visibleTasks) {
    setState(() {
      if (_selectedTaskIds.length == visibleTasks.length) {
        _selectedTaskIds.clear();
      } else {
        _selectedTaskIds.clear();
        _selectedTaskIds.addAll(visibleTasks.map((t) => t.id));
      }
    });
  }

  Future<void> _bulkPause() async {
    for (final id in _selectedTaskIds) {
      await widget.manager.pauseDownload(id);
    }
  }

  Future<void> _bulkResume() async {
    for (final id in _selectedTaskIds) {
      await widget.manager.resumeDownload(id);
    }
  }

  void _handleToolbarDelete(BuildContext context) {
    if (_isSelectionMode) {
      _bulkDelete();
    } else {
      _confirmClearCompleted(context);
    }
  }

  Future<void> _showQueueSchedulerDialog(BuildContext context) async {
    String selectedQueue = widget.manager.namedQueues.first;
    var schedule = widget.manager.getQueueSchedule(selectedQueue);
    int startHour = schedule?.startHour ?? 2;
    int startMinute = schedule?.startMinute ?? 0;
    int stopHour = schedule?.stopHour ?? 6;
    int stopMinute = schedule?.stopMinute ?? 0;
    bool isEnabled = schedule?.isEnabled ?? false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20),
              SizedBox(width: 8),
              Text('Queue Scheduler'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedQueue,
                decoration: const InputDecoration(labelText: 'Named Queue'),
                items: widget.manager.namedQueues
                    .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      selectedQueue = val;
                      final s = widget.manager.getQueueSchedule(val);
                      startHour = s?.startHour ?? 2;
                      startMinute = s?.startMinute ?? 0;
                      stopHour = s?.stopHour ?? 6;
                      stopMinute = s?.stopMinute ?? 0;
                      isEnabled = s?.isEnabled ?? false;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable Auto Schedule',
                  style: TextStyle(fontSize: 13),
                ),
                value: isEnabled,
                onChanged: (val) => setDialogState(() => isEnabled = val),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.play_arrow_outlined,
                  color: Colors.green,
                ),
                title: const Text('Start Time', style: TextStyle(fontSize: 13)),
                trailing: TextButton(
                  child: Text(
                    '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                  ),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(
                        hour: startHour,
                        minute: startMinute,
                      ),
                    );
                    if (t != null) {
                      setDialogState(() {
                        startHour = t.hour;
                        startMinute = t.minute;
                      });
                    }
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop_outlined, color: Colors.red),
                title: const Text('Stop Time', style: TextStyle(fontSize: 13)),
                trailing: TextButton(
                  child: Text(
                    '${stopHour.toString().padLeft(2, '0')}:${stopMinute.toString().padLeft(2, '0')}',
                  ),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(
                        hour: stopHour,
                        minute: stopMinute,
                      ),
                    );
                    if (t != null) {
                      setDialogState(() {
                        stopHour = t.hour;
                        stopMinute = t.minute;
                      });
                    }
                  },
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
              onPressed: () {
                widget.manager.setQueueSchedule(
                  QueueSchedule(
                    queueName: selectedQueue,
                    startHour: startHour,
                    startMinute: startMinute,
                    stopHour: stopHour,
                    stopMinute: stopMinute,
                    isEnabled: isEnabled,
                  ),
                );
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Schedule updated for "$selectedQueue"'),
                  ),
                );
              },
              child: const Text('Save Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkDelete() async {
    final count = _selectedTaskIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Downloads'),
        content: Text('Remove $count selected downloads from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedTaskIds.toList()) {
        await widget.manager.deleteTask(id, deleteFile: false);
      }
      setState(() {
        _selectedTaskIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: AppShortcuts.shortcuts,
      child: Actions(
        actions: {
          AddNewDownloadIntent: CallbackAction<AddNewDownloadIntent>(
            onInvoke: (_) {
              _showAddSheet();
              return null;
            },
          ),
          TogglePauseResumeIntent: CallbackAction<TogglePauseResumeIntent>(
            onInvoke: (_) {
              if (widget.manager.activeTasks.isNotEmpty) {
                widget.manager.pauseAll();
              } else {
                widget.manager.resumeAll();
              }
              return null;
            },
          ),
          DeleteSelectedIntent: CallbackAction<DeleteSelectedIntent>(
            onInvoke: (_) {
              if (_isSelectionMode) {
                _bulkDelete();
              }
              return null;
            },
          ),
          SelectAllIntent: CallbackAction<SelectAllIntent>(
            onInvoke: (_) {
              _toggleSelectAll(_getFilteredTasks());
              return null;
            },
          ),
          EscapeIntent: CallbackAction<EscapeIntent>(
            onInvoke: (_) {
              setState(() {
                _selectedTaskIds.clear();
              });
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) {
              final filteredTasks = _getFilteredTasks();

              // Wide screen check: >= 900 dp width (tablet landscape, Chromebook, desktop)
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWideScreen = constraints.maxWidth >= 900;
                  final isUltraWide = constraints.maxWidth >= 1200;

                  return Scaffold(
                    appBar: _buildAppBar(context, filteredTasks),
                    body: isWideScreen
                        ? _buildWideScreenLayout(
                            context,
                            filteredTasks,
                            isUltraWide,
                          )
                        : _buildMobileLayout(context, filteredTasks),
                    floatingActionButton: isWideScreen
                        ? null
                        : FloatingActionButton.extended(
                            onPressed: () => _showAddSheet(),
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('Add Link'),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    List<DownloadTask> visibleTasks,
  ) {
    final theme = Theme.of(context);

    if (_isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() => _selectedTaskIds.clear()),
        ),
        title: Text('${_selectedTaskIds.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            tooltip: 'Select All',
            onPressed: () => _toggleSelectAll(visibleTasks),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: 'Resume Selected',
            onPressed: _bulkResume,
          ),
          IconButton(
            icon: const Icon(Icons.pause_rounded),
            tooltip: 'Pause Selected',
            onPressed: _bulkPause,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Selected',
            onPressed: _bulkDelete,
          ),
        ],
      );
    }

    return AppBar(
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
                  'PRO',
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
            } else if (value == 'scheduler') {
              _showQueueSchedulerDialog(context);
            } else if (value == 'about') {
              _showAboutDialog(context);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'scheduler',
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Queue Scheduler'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear_completed',
              enabled: widget.manager.completedTasks.isNotEmpty,
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
    );
  }

  // --- WIDE SCREEN MULTI-PANE LAYOUT ---
  Widget _buildWideScreenLayout(
    BuildContext context,
    List<DownloadTask> filteredTasks,
    bool isUltraWide,
  ) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // Left NavigationRail: Categories & Queues (wrapped in scrollview for safety)
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 400),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: DownloadCategory.values.indexOf(
                  _selectedCategory,
                ),
                onDestinationSelected: (idx) {
                  setState(() {
                    _selectedCategory = DownloadCategory.values[idx];
                  });
                },
                labelType: NavigationRailLabelType.all,
                leading: FloatingActionButton.small(
                  onPressed: () => _showAddSheet(),
                  tooltip: 'Add Link (Ctrl+N)',
                  child: const Icon(Icons.add_rounded),
                ),
                destinations: DownloadCategory.values.map((cat) {
                  return NavigationRailDestination(
                    icon: Icon(NetGetUtils.getCategoryIcon(cat)),
                    label: Text(
                      cat.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),

        // Center Pane: Master Download List with Toolbar
        Expanded(
          flex: isUltraWide ? 5 : 6,
          child: Column(
            children: [
              StatsSummaryCard(
                manager: widget.manager,
                isDense: _isDense,
                onToggleDense: () => setState(() => _isDense = !_isDense),
                onAddLink: () => _showAddSheet(),
                onDeleteSelected: () => _handleToolbarDelete(context),
              ),

              // Filter Tabs & Search / Sort Row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) =>
                              setState(() => _searchQuery = val.trim()),
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search downloads...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 16,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    PopupMenuButton<_SortOption>(
                      initialValue: _sortOption,
                      tooltip: 'Sort by',
                      icon: const Icon(Icons.sort_rounded, size: 20),
                      onSelected: (opt) => setState(() => _sortOption = opt),
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: _SortOption.dateDesc,
                          child: Text('Date (Newest first)'),
                        ),
                        PopupMenuItem(
                          value: _SortOption.dateAsc,
                          child: Text('Date (Oldest first)'),
                        ),
                        PopupMenuItem(
                          value: _SortOption.nameAsc,
                          child: Text('Name (A - Z)'),
                        ),
                        PopupMenuItem(
                          value: _SortOption.sizeDesc,
                          child: Text('Size (Largest first)'),
                        ),
                        PopupMenuItem(
                          value: _SortOption.speedDesc,
                          child: Text('Speed (Fastest first)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filter Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children:
                      [
                        _FilterTab.all,
                        _FilterTab.active,
                        _FilterTab.completed,
                        _FilterTab.queued,
                        _FilterTab.paused,
                        _FilterTab.failed,
                      ].map((tab) {
                        final isSelected = _selectedTab == tab;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            selected: isSelected,
                            label: Text(_filterTabLabel(tab)),
                            onSelected: (_) =>
                                setState(() => _selectedTab = tab),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }).toList(),
                ),
              ),

              // Download List
              Expanded(
                child: filteredTasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          final isCurrent = task.id == _selectedTaskId;
                          return DownloadCard(
                            key: ValueKey(task.id),
                            task: task,
                            manager: widget.manager,
                            isDense: _isDense,
                            isSelected: _isSelectionMode
                                ? _selectedTaskIds.contains(task.id)
                                : isCurrent,
                            isSelectionMode: _isSelectionMode,
                            onTap: () {
                              setState(() {
                                _selectedTaskId = task.id;
                              });
                            },
                            onSelectChanged: (sel) {
                              setState(() {
                                if (sel) {
                                  _selectedTaskIds.add(task.id);
                                } else {
                                  _selectedTaskIds.remove(task.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),

        // Right Pane: Details Pane for Selected Task
        Expanded(
          flex: isUltraWide ? 5 : 5,
          child:
              _selectedTaskId != null &&
                  widget.manager.tasks.any((t) => t.id == _selectedTaskId)
              ? DownloadDetailsScreen(
                  key: ValueKey(_selectedTaskId),
                  manager: widget.manager,
                  taskId: _selectedTaskId!,
                  isPaneMode: true,
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Select a download to inspect live segments & properties',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // --- MOBILE SINGLE-PANE LAYOUT ---
  Widget _buildMobileLayout(
    BuildContext context,
    List<DownloadTask> filteredTasks,
  ) {
    final allCount = widget.manager.tasks.length;
    final activeCount = widget.manager.tasks
        .where((t) => !t.status.isCompleted)
        .length;
    final completedCount = widget.manager.completedTasks.length;

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
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

          // Monitor Summary & Toolbar
          SliverToBoxAdapter(
            child: StatsSummaryCard(
              manager: widget.manager,
              isDense: _isDense,
              onToggleDense: () => setState(() => _isDense = !_isDense),
              onAddLink: () => _showAddSheet(),
              onDeleteSelected: () => _handleToolbarDelete(context),
            ),
          ),

          // Categories Filter Chips
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: DownloadCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat.label),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Segmented Button Tabs Bar
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
                selected: {
                  _selectedTab == _FilterTab.completed
                      ? _FilterTab.completed
                      : (_selectedTab == _FilterTab.active
                            ? _FilterTab.active
                            : _FilterTab.all),
                },
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
            SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 4, bottom: 88),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final task = filteredTasks[index];
                  return DownloadCard(
                    key: ValueKey(task.id),
                    task: task,
                    manager: widget.manager,
                    isDense: _isDense,
                    isSelected: _selectedTaskIds.contains(task.id),
                    isSelectionMode: _isSelectionMode,
                    onSelectChanged: (sel) {
                      setState(() {
                        if (sel) {
                          _selectedTaskIds.add(task.id);
                        } else {
                          _selectedTaskIds.remove(task.id);
                        }
                      });
                    },
                  );
                }, childCount: filteredTasks.length),
              ),
            ),
        ],
      ),
    );
  }

  String _filterTabLabel(_FilterTab tab) {
    switch (tab) {
      case _FilterTab.all:
        return 'All (${widget.manager.tasks.length})';
      case _FilterTab.active:
        return 'Active (${widget.manager.tasks.where((t) => !t.status.isCompleted).length})';
      case _FilterTab.completed:
        return 'Done (${widget.manager.completedTasks.length})';
      case _FilterTab.queued:
        return 'Queued (${widget.manager.queuedCount})';
      case _FilterTab.paused:
        return 'Paused (${widget.manager.pausedTasks.length})';
      case _FilterTab.failed:
        return 'Failed (${widget.manager.failedTasks.length})';
    }
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
          onButtonPressed: () => _showAddSheet(),
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
          message:
              'Finished downloads will appear here with 1-tap open and share.',
        );
      case _FilterTab.queued:
        return const EmptyStateView(
          icon: Icons.hourglass_empty_rounded,
          title: 'No Queued Downloads',
          message: 'Pending items waiting for bandwidth will show here.',
        );
      case _FilterTab.paused:
        return const EmptyStateView(
          icon: Icons.pause_circle_outline_rounded,
          title: 'No Paused Downloads',
          message: 'Paused items waiting to resume will show here.',
        );
      case _FilterTab.failed:
        return const EmptyStateView(
          icon: Icons.error_outline_rounded,
          title: 'No Failed Downloads',
          message: 'All downloads succeeded without error.',
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
      applicationVersion: '2.0.0',
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/branding/netget_store_icon_512.png',
          width: 44,
          height: 44,
          errorBuilder: (_, _, _) => Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NetGetTheme.brandNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.download_rounded,
              color: NetGetTheme.brandGreen,
              size: 28,
            ),
          ),
        ),
      ),
      children: const [
        Text(
          'NetGet is a lightweight, fast, and dense Android download manager '
          'inspired by classic desktop tools (IDM & FDM). Features live 60s speed graph, '
          'segmented connection map, dynamic re-splitting, desktop shortcuts, '
          'and clean Material 3 design.',
        ),
      ],
    );
  }
}
