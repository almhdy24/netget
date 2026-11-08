import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';

Future<void> showNetGetAboutDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final colorScheme = theme.colorScheme;

      return AlertDialog(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.download, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(NetGetConstants.appName),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              NetGetConstants.appFullName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Version ${NetGetConstants.appVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A fast, compact Android download manager inspired by classic desktop tools (IDM & FDM). '
              'Features multi-connection segmented downloads, live 60-sample speed graph, '
              'connection map, and resilient queue management.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _showLicenses(ctx),
            child: const Text('Licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

void _showLicenses(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Licenses')),
        body: FutureBuilder<List<LicenseEntry>>(
          future: LicenseRegistry.licenses.toList(),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return const Center(child: Text('No licenses found'));
            }
            final packageMap = <String, List<String>>{};
            for (final entry in entries) {
              for (final pkg in entry.packages) {
                final text = entry.paragraphs.map((p) => p.text).join('\n\n');
                packageMap.putIfAbsent(pkg, () => []).add(text);
              }
            }
            final packageNames = packageMap.keys.toList()..sort();
            return ListView.separated(
              itemCount: packageNames.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final pkg = packageNames[index];
                final texts = packageMap[pkg]!;
                return ExpansionTile(
                  title: Text(
                    pkg,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${texts.length} license ${texts.length == 1 ? "entry" : "entries"}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SelectableText(
                        texts.join('\n\n---\n\n'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
