import 'package:flutter/material.dart';

class SelectionActionBar extends StatelessWidget
    implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onClearSelection;
  final VoidCallback onSelectAll;
  final VoidCallback onResumeSelected;
  final VoidCallback onPauseSelected;
  final VoidCallback onDeleteSelected;

  const SelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    required this.onSelectAll,
    required this.onResumeSelected,
    required this.onPauseSelected,
    required this.onDeleteSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close, size: 20),
        tooltip: 'Cancel selection',
        onPressed: onClearSelection,
      ),
      title: Text(
        '$selectedCount selected',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all, size: 20),
          tooltip: 'Select all',
          onPressed: onSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.play_arrow, size: 20),
          tooltip: 'Resume selected',
          onPressed: onResumeSelected,
        ),
        IconButton(
          icon: const Icon(Icons.pause, size: 20),
          tooltip: 'Pause selected',
          onPressed: onPauseSelected,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
          tooltip: 'Delete selected',
          onPressed: onDeleteSelected,
        ),
      ],
    );
  }
}
