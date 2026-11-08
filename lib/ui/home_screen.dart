import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../data/settings_repository.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';
import '../services/analytics_service.dart';
import '../services/download_manager.dart';
import '../services/notification_permission_service.dart';
import 'details/download_details_screen.dart';
import 'dialogs/about_dialog.dart';
import 'dialogs/analytics_prompt_dialog.dart';
import 'dialogs/queue_scheduler_dialog.dart';
import 'dialogs/theme_dialog.dart';
import 'settings/settings_dialog.dart';
import 'shortcuts/app_shortcuts.dart';
import 'widgets/add_download_sheet.dart';
import 'widgets/category_sidebar.dart';
import 'widgets/desktop_toolbar.dart';
import 'widgets/download_card.dart';
import 'widgets/download_status_footer.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/notification_permission_banner.dart';
import 'widgets/selection_action_bar.dart';

enum _FilterTab { all, active, completed, queued, paused, failed }

enum _SortOption { dateDesc, dateAsc, nameAsc, sizeDesc, speedDesc }

class HomeScreen extends StatefulWidget {
  final DownloadManager manager;
  final ValueNotifier<ThemeMode> themeModeNotifier;
  final NotificationPermissionService? permissionService;
  final SettingsRepository? settingsRepository;

  const HomeScreen({
    super.key,
    required this.manager,
    required this.themeModeNotifier,
    this.permissionService,
    this.settingsRepository,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _FilterTab _selectedTab = _FilterTab.all;
  DownloadCategory _selectedCategory = DownloadCategory.all;
  _SortOption _sortOption = _SortOption.dateDesc;
  bool _isDense = false;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _selectedTaskIds = {};
  bool get _isSelectionMode => _selectedTaskIds.isNotEmpty;

  String? _selectedTaskId;
  late final NotificationPermissionService _permissionService;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('home');
    _permissionService =
        widget.permissionService ?? NotificationPermissionService();
    _permissionService.addListener(_onPermissionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.settingsRepository != null) {
        showFirstRunAnalyticsPrompt(context, widget.settingsRepository!);
      }
    });
  }

  void _onPermissionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _permissionService.removeListener(_onPermissionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _showAddSheet({String? initialUrl}) {
    AddDownloadSheet.show(
      context,
      manager: widget.manager,
      permissionService: _permissionService,
      initialUrl: initialUrl,
      onOpenExisting: (task) {
        setState(() => _selectedTaskId = task.id);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                DownloadDetailsScreen(manager: widget.manager, taskId: task.id),
          ),
        );
      },
    );
  }

  List<DownloadTask> _getFilteredTasks() {
    var list = List<DownloadTask>.from(widget.manager.tasks);

    // Filter by tab
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

    // Sort
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

  Map<DownloadCategory, int> _getCategoryCounts() {
    final counts = <DownloadCategory, int>{};
    for (final task in widget.manager.tasks) {
      counts[task.category] = (counts[task.category] ?? 0) + 1;
    }
    counts[DownloadCategory.all] = widget.manager.tasks.length;
    return counts;
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

  void _bulkResume() {
    for (final id in _selectedTaskIds) {
      widget.manager.resumeDownload(id);
    }
  }

  void _bulkPause() {
    for (final id in _selectedTaskIds) {
      widget.manager.pauseDownload(id);
    }
  }

  Future<void> _bulkDelete() async {
    final count = _selectedTaskIds.length;
    var alsoDeleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Downloads'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove $count selected downloads?'),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoDeleteFiles,
                title: const Text(
                  'Also delete downloaded files from disk',
                  style: TextStyle(fontSize: 12.5),
                ),
                onChanged: (val) {
                  setDialogState(() => alsoDeleteFiles = val ?? false);
                },
              ),
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
        ),
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedTaskIds.toList()) {
        await widget.manager.deleteTask(id, deleteFile: alsoDeleteFiles);
      }
      setState(() {
        _selectedTaskIds.clear();
        _selectedTaskId = null;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth >= 768;
              final filteredTasks = _getFilteredTasks();

              return Scaffold(
                appBar: _isSelectionMode
                    ? SelectionActionBar(
                        selectedCount: _selectedTaskIds.length,
                        onClearSelection: () =>
                            setState(() => _selectedTaskIds.clear()),
                        onSelectAll: () => _toggleSelectAll(filteredTasks),
                        onResumeSelected: _bulkResume,
                        onPauseSelected: _bulkPause,
                        onDeleteSelected: _bulkDelete,
                      )
                    : _buildStandardAppBar(context),
                body: Column(
                  children: [
                    // Utilitarian desktop toolbar
                    DesktopToolbar(
                      manager: widget.manager,
                      onAddLink: () => _showAddSheet(),
                      onOpenSettings: () => SettingsDialog.show(
                        context,
                        settingsRepository: widget.settingsRepository,
                        themeModeNotifier: widget.themeModeNotifier,
                      ),
                      isSelectionMode: _isSelectionMode,
                      onDeleteSelected: _bulkDelete,
                      isDense: _isDense,
                      onToggleDense: () => setState(() => _isDense = !_isDense),
                    ),

                    // Notification banner if permission missing
                    NotificationPermissionBanner(
                      permissionService: _permissionService,
                    ),

                    // Main view (Wide screen layout vs Mobile layout)
                    Expanded(
                      child: isWideScreen
                          ? _buildWideScreenLayout(context)
                          : _buildMobileLayout(context),
                    ),

                    // Compact status footer
                    DownloadStatusFooter(manager: widget.manager),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildStandardAppBar(BuildContext context) {
    if (_isSearchOpen) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () {
            setState(() {
              _isSearchOpen = false;
              _searchQuery = '';
              _searchController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Search downloads by name or URL...',
            border: InputBorder.none,
          ),
          onChanged: (q) => setState(() => _searchQuery = q.trim()),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
        ],
      );
    }

    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.download, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              NetGetConstants.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, size: 20),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearchOpen = true),
        ),
        PopupMenuButton<_SortOption>(
          icon: const Icon(Icons.sort, size: 20),
          tooltip: 'Sort by',
          initialValue: _sortOption,
          onSelected: (opt) => setState(() => _sortOption = opt),
          itemBuilder: (context) => const [
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
              child: Text('File Name (A-Z)'),
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
        IconButton(
          icon: const Icon(Icons.schedule, size: 20),
          tooltip: 'Queue scheduler',
          onPressed: () => showQueueSchedulerDialog(context, widget.manager),
        ),
        IconButton(
          icon: const Icon(Icons.palette_outlined, size: 20),
          tooltip: 'Theme',
          onPressed: () =>
              showThemeSelectionDialog(context, widget.themeModeNotifier),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 20),
          tooltip: 'About NetGet',
          onPressed: () => showNetGetAboutDialog(context),
        ),
      ],
    );
  }

  Widget _buildWideScreenLayout(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final filteredTasks = _getFilteredTasks();
        final counts = _getCategoryCounts();

        return Row(
          children: [
            // Left category navigation rail
            CategorySidebar(
              isRail: true,
              selectedCategory: _selectedCategory,
              categoryCounts: counts,
              onCategorySelected: (cat) =>
                  setState(() => _selectedCategory = cat),
            ),

            // Middle: Task list
            Expanded(flex: 5, child: _buildTaskList(context, filteredTasks)),

            // Right: Detail pane if a task is selected
            if (_selectedTaskId != null) ...[
              const VerticalDivider(width: 1),
              Expanded(
                flex: 4,
                child: DownloadDetailsScreen(
                  manager: widget.manager,
                  taskId: _selectedTaskId!,
                  isPaneMode: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final filteredTasks = _getFilteredTasks();
        final counts = _getCategoryCounts();

        return Column(
          children: [
            // Category choice chips
            CategorySidebar(
              isRail: false,
              selectedCategory: _selectedCategory,
              categoryCounts: counts,
              onCategorySelected: (cat) =>
                  setState(() => _selectedCategory = cat),
            ),

            // Filter Tabs (All, Active, Completed, Queued, Paused, Failed)
            _buildFilterTabBar(context),

            // Download list
            Expanded(child: _buildTaskList(context, filteredTasks)),
          ],
        );
      },
    );
  }

  Widget _buildFilterTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final tab in _FilterTab.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton(
                onPressed: () => setState(() => _selectedTab = tab),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 26),
                  backgroundColor: _selectedTab == tab
                      ? colorScheme.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                ),
                child: Text(
                  tab.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: _selectedTab == tab
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: _selectedTab == tab
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskList(
    BuildContext context,
    List<DownloadTask> filteredTasks,
  ) {
    if (filteredTasks.isEmpty) {
      return EmptyStateView(
        icon: Icons.inbox_outlined,
        title: _searchQuery.isNotEmpty
            ? 'No matching downloads'
            : 'No downloads in this category',
        message: _searchQuery.isNotEmpty
            ? 'Try searching with a different term'
            : 'Add a new download URL using the toolbar above.',
        buttonText: 'Add URL',
        onButtonPressed: () => _showAddSheet(),
        onPasteUrl: (url) => _showAddSheet(initialUrl: url),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
            setState(() => _selectedTaskId = task.id);
            final isWideScreen = MediaQuery.sizeOf(context).width >= 768;
            if (!isWideScreen) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DownloadDetailsScreen(
                    manager: widget.manager,
                    taskId: task.id,
                  ),
                ),
              );
            }
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
    );
  }
}
