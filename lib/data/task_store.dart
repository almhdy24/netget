import 'package:flutter/foundation.dart';
import '../models/download_task.dart';

typedef TaskChangeListener = void Function();
typedef TaskPersistCallback = void Function(DownloadTask task);
typedef TasksPersistCallback = void Function(List<DownloadTask> tasks);

/// Dedicated single mutation path for tasks.
///
/// Prevents stale-index corruption by finding tasks by ID at modification time,
/// maintains per-task ValueNotifiers for granular UI rebuilds,
/// and coordinates persistence and aggregate notifications.
class TaskStore {
  final List<DownloadTask> _tasks = [];
  final Map<String, ValueNotifier<DownloadTask>> _notifiers = {};

  final VoidCallback? onTasksChanged;
  final TaskPersistCallback? onTaskPersist;
  final TasksPersistCallback? onScheduleSave;

  TaskStore({this.onTasksChanged, this.onTaskPersist, this.onScheduleSave});

  /// Unmodifiable view of tasks in the store.
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get length => _tasks.length;
  bool get isEmpty => _tasks.isEmpty;
  bool get isNotEmpty => _tasks.isNotEmpty;

  /// Initializes the store with a loaded list of tasks.
  void init(List<DownloadTask> initialTasks) {
    _tasks.clear();
    _tasks.addAll(initialTasks);

    for (final task in initialTasks) {
      final existingNotifier = _notifiers[task.id];
      if (existingNotifier != null) {
        if (existingNotifier.value != task) {
          existingNotifier.value = task;
        }
      }
    }

    // Clean up notifiers for tasks that no longer exist
    _notifiers.removeWhere((id, notifier) {
      final stillExists = _tasks.any((t) => t.id == id);
      if (!stillExists) {
        notifier.dispose();
      }
      return !stillExists;
    });
  }

  /// Finds a task by ID at call time. Returns null if not found.
  DownloadTask? getById(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;
    return _tasks[idx];
  }

  /// Checks if a task exists in the store.
  bool contains(String id) => _tasks.any((t) => t.id == id);

  /// Atomic mutation: finds the task by ID AT CALL TIME, applies [updater],
  /// replaces it in the list, updates the per-task ValueNotifier,
  /// schedules persistence, and optionally triggers an aggregate notification.
  DownloadTask? update(
    String id,
    DownloadTask Function(DownloadTask current) updater, {
    bool notifyAggregate = false,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;

    final current = _tasks[idx];
    final updated = updater(current);

    // If no data changed, avoid redundant notifications
    if (updated == current) return current;

    _tasks[idx] = updated;

    final notifier = _notifiers[id];
    if (notifier != null && notifier.value != updated) {
      notifier.value = updated;
    }

    onTaskPersist?.call(updated);
    onScheduleSave?.call(_tasks);

    if (notifyAggregate) {
      onTasksChanged?.call();
    }

    return updated;
  }

  /// Adds a task to the store.
  void add(DownloadTask task, {int? index, bool notifyAggregate = true}) {
    if (index != null && index >= 0 && index <= _tasks.length) {
      _tasks.insert(index, task);
    } else {
      _tasks.insert(0, task);
    }

    if (_notifiers.containsKey(task.id)) {
      _notifiers[task.id]!.value = task;
    } else {
      _notifiers[task.id] = ValueNotifier<DownloadTask>(task);
    }

    onTaskPersist?.call(task);
    onScheduleSave?.call(_tasks);

    if (notifyAggregate) {
      onTasksChanged?.call();
    }
  }

  /// Removes a task by ID.
  DownloadTask? remove(String id, {bool notifyAggregate = true}) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;

    final removed = _tasks.removeAt(idx);
    final notifier = _notifiers.remove(id);
    notifier?.dispose();

    onScheduleSave?.call(_tasks);

    if (notifyAggregate) {
      onTasksChanged?.call();
    }

    return removed;
  }

  /// Removes all tasks satisfying [predicate].
  List<DownloadTask> removeWhere(
    bool Function(DownloadTask task) predicate, {
    bool notifyAggregate = true,
  }) {
    final removed = <DownloadTask>[];
    _tasks.removeWhere((t) {
      if (predicate(t)) {
        removed.add(t);
        final notifier = _notifiers.remove(t.id);
        notifier?.dispose();
        return true;
      }
      return false;
    });

    if (removed.isNotEmpty) {
      onScheduleSave?.call(_tasks);
      if (notifyAggregate) {
        onTasksChanged?.call();
      }
    }

    return removed;
  }

  /// Retrieves a task-specific ValueNotifier if the task exists.
  /// Does NOT create placeholder tasks or mutate notifiers inside this getter.
  ValueNotifier<DownloadTask>? getNotifier(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return null;

    return _notifiers.putIfAbsent(
      taskId,
      () => ValueNotifier<DownloadTask>(_tasks[idx]),
    );
  }

  /// Cleans up all managed notifiers and cleared tasks.
  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _tasks.clear();
  }
}
