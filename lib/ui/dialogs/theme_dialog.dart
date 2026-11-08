import 'package:flutter/material.dart';

Future<void> showThemeSelectionDialog(
  BuildContext context,
  ValueNotifier<ThemeMode> themeModeNotifier,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final currentMode = themeModeNotifier.value;
      final theme = Theme.of(ctx);

      Widget buildOption({
        required ThemeMode mode,
        required String title,
        required String subtitle,
        required IconData icon,
      }) {
        final isSelected = currentMode == mode;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () {
                Navigator.of(ctx).pop();
                themeModeNotifier.value = mode;
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 1.5 : 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.palette_outlined, size: 20),
            SizedBox(width: 8),
            Text('Appearance'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildOption(
              mode: ThemeMode.system,
              title: 'System default',
              subtitle: 'Follow device settings',
              icon: Icons.brightness_auto_outlined,
            ),
            buildOption(
              mode: ThemeMode.light,
              title: 'Light',
              subtitle: 'Classic light desktop interface',
              icon: Icons.light_mode_outlined,
            ),
            buildOption(
              mode: ThemeMode.dark,
              title: 'Dark',
              subtitle: 'Dark desktop interface',
              icon: Icons.dark_mode_outlined,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
