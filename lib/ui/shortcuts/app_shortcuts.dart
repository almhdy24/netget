import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddNewDownloadIntent extends Intent {
  const AddNewDownloadIntent();
}

class TogglePauseResumeIntent extends Intent {
  const TogglePauseResumeIntent();
}

class DeleteSelectedIntent extends Intent {
  const DeleteSelectedIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class AppShortcuts {
  static final Map<ShortcutActivator, Intent> shortcuts = {
    // Ctrl+N / Cmd+N -> Add New Download
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
        const AddNewDownloadIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
        const AddNewDownloadIntent(),

    // Space -> Pause / Resume
    LogicalKeySet(LogicalKeyboardKey.space): const TogglePauseResumeIntent(),

    // Delete / Backspace -> Delete
    LogicalKeySet(LogicalKeyboardKey.delete): const DeleteSelectedIntent(),

    // Ctrl+A / Cmd+A -> Select All
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
        const SelectAllIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA):
        const SelectAllIntent(),

    // Escape -> Clear selection / cancel
    LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
  };
}
