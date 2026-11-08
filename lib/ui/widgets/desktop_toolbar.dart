import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../services/download_manager.dart';

/// Classic utilitarian toolbar (IDM / FDM style) with standard download actions:
/// Add URL, Resume All, Pause All, Delete Completed, Settings.
class DesktopToolbar extends StatelessWidget {
  final DownloadManager manager;
  final VoidCallback onAddLink;
  final VoidCallback onOpenSettings;
  final VoidCallback? onDeleteSelected;
  final bool isSelectionMode;
  final bool isDense;
  final VoidCallback onToggleDense;

  const DesktopToolbar({
    super.key,
    required this.manager,
    required this.onAddLink,
    required this.onOpenSettings,
    this.onDeleteSelected,
    this.isSelectionMode = false,
    this.isDense = false,
    required this.onToggleDense,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasActive = manager.activeTasks.isNotEmpty;
    final hasPaused = manager.pausedTasks.isNotEmpty;

    return Container(
      height: 42,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // Add Download
          _ToolbarButton(
            icon: Icons.add,
            tooltip: 'Add URL (Ctrl+N)',
            label: 'Add URL',
            onPressed: onAddLink,
          ),
          const SizedBox(width: 4),
          _buildDivider(colorScheme),
          const SizedBox(width: 4),

          // Resume All
          _ToolbarButton(
            icon: Icons.play_arrow,
            tooltip: 'Resume all',
            label: 'Resume all',
            enabled: hasPaused,
            onPressed: hasPaused ? () => manager.resumeAll() : null,
          ),

          // Pause All
          _ToolbarButton(
            icon: Icons.pause,
            tooltip: 'Pause all',
            label: 'Pause all',
            enabled: hasActive,
            onPressed: hasActive ? () => manager.pauseAll() : null,
          ),

          // Delete
          if (isSelectionMode && onDeleteSelected != null) ...[
            _ToolbarButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete selected',
              label: 'Delete',
              iconColor: colorScheme.error,
              onPressed: onDeleteSelected,
            ),
          ],

          const Spacer(),

          // Toggle dense / normal list view
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              isDense ? Icons.view_agenda_outlined : Icons.table_rows_outlined,
              size: 18,
            ),
            tooltip: isDense ? 'Card view' : 'Table view',
            onPressed: onToggleDense,
          ),

          // Speed limit mode dropdown
          _buildSpeedModeMenu(context),

          // Settings
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'Settings',
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedModeMenu(BuildContext context) {
    return PopupMenuButton<SpeedMode>(
      tooltip: 'Speed limiter',
      initialValue: manager.speedMode,
      icon: const Icon(Icons.speed_outlined, size: 18),
      onSelected: (mode) => manager.setSpeedMode(mode),
      itemBuilder: (context) => [
        for (final mode in SpeedMode.values)
          PopupMenuItem<SpeedMode>(value: mode, child: Text(mode.label)),
      ],
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(width: 1, height: 18, color: colorScheme.outlineVariant);
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? iconColor;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.label,
    this.onPressed,
    this.enabled = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

    final color = enabled
        ? (iconColor ?? colorScheme.onSurface)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);

    if (isDesktop && label != null) {
      return TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
        ),
      );
    }

    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
