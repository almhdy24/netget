import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final void Function(String url)? onPasteUrl;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onButtonPressed,
    this.onPasteUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? NetGetTheme.brandNavy
                    : theme.colorScheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                  color: isDark
                      ? NetGetTheme.brandCyan.withValues(alpha: 0.2)
                      : theme.colorScheme.primary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                size: 44,
                color: isDark
                    ? NetGetTheme.brandCyan
                    : theme.colorScheme.primary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            if (buttonText != null && onButtonPressed != null)
              FilledButton.icon(
                onPressed: onButtonPressed,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(buttonText!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(160, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            if (onPasteUrl != null) ...[
              const SizedBox(height: 12),
              ActionChip(
                avatar: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('Paste from clipboard'),
                onPressed: () async {
                  // Explicit user tap only - never read clipboard in background
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim() ?? '';
                  if (text.startsWith('http://') || text.startsWith('https://')) {
                    onPasteUrl!(text);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Clipboard does not contain a valid URL'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
