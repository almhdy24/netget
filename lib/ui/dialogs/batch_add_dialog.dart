import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../models/data_budget.dart';
import '../../services/download_manager.dart';

class BatchAddDialog extends StatefulWidget {
  final DownloadManager manager;
  final String? initialText;

  const BatchAddDialog({super.key, required this.manager, this.initialText});

  static Future<void> show(
    BuildContext context, {
    required DownloadManager manager,
    String? initialText,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) =>
          BatchAddDialog(manager: manager, initialText: initialText),
    );
  }

  @override
  State<BatchAddDialog> createState() => _BatchAddDialogState();
}

class _BatchAddDialogState extends State<BatchAddDialog> {
  late final TextEditingController _urlsController;
  NetworkPolicy _selectedPolicy = NetworkPolicy.anyNetwork;
  final String _selectedQueue = NetGetConstants.defaultQueueName;
  bool _startNow = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPolicy = widget.manager.settings.defaultNetworkPolicy;
    _urlsController = TextEditingController(text: widget.initialText ?? '');
    _urlsController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlsController.dispose();
    super.dispose();
  }

  List<String> get _parsedUrls {
    final text = _urlsController.text;
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) {
          final uri = Uri.tryParse(line);
          return uri != null &&
              (uri.isScheme('http') || uri.isScheme('https')) &&
              uri.host.isNotEmpty;
        })
        .toSet()
        .toList();
  }

  Future<void> _submit() async {
    final urls = _parsedUrls;
    if (urls.isEmpty) return;

    setState(() => _isSubmitting = true);

    int addedCount = 0;
    for (final url in urls) {
      try {
        final fileName = NetGetUtils.extractFileNameFromUrl(url);
        final category = NetGetUtils.classifyCategory(fileName);
        await widget.manager.addDownload(
          url: url,
          queueName: _selectedQueue,
          category: category,
          networkPolicy: _selectedPolicy,
          startNow: _startNow,
          source: 'batch',
        );
        addedCount++;
      } catch (e) {
        debugPrint('Batch add error for $url: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Directionality.of(context) == TextDirection.rtl
                ? 'تمت إضافة $addedCount من الروابط إلى قائمة التنزيلات'
                : 'Added $addedCount downloads to queue',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final urls = _parsedUrls;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.playlist_add_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(isRtl ? 'إضافة دفعة روابط (Batch Add)' : 'Batch Add Downloads'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRtl
                    ? 'الصق روابط التنزيل (رابط في كل سطر):'
                    : 'Paste download links (one URL per line):',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlsController,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText:
                      'https://example.com/file1.zip\nhttps://example.com/file2.mp4',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: const OutlineInputBorder(),
                  helperText: isRtl
                      ? 'تم التعرف على ${urls.length} رابط صحيح'
                      : '${urls.length} valid URLs recognized',
                ),
              ),
              const SizedBox(height: 16),

              // Network Policy Selector
              Text(
                isRtl ? 'سياسة الشبكة:' : 'Network Policy:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<NetworkPolicy>(
                segments: [
                  ButtonSegment(
                    value: NetworkPolicy.anyNetwork,
                    label: Text(isRtl ? 'أي شبكة' : 'Any Net'),
                  ),
                  ButtonSegment(
                    value: NetworkPolicy.wifiOnly,
                    label: Text(isRtl ? 'واي-فاي فقط' : 'Wi-Fi Only'),
                  ),
                  ButtonSegment(
                    value: NetworkPolicy.wifiOrFreeWindow,
                    label: Text(isRtl ? 'ليلي / مجاني' : 'Night/Free'),
                  ),
                ],
                selected: {_selectedPolicy},
                onSelectionChanged: (sel) {
                  setState(() => _selectedPolicy = sel.first);
                },
              ),
              const SizedBox(height: 14),

              // Start Now Checkbox
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  isRtl ? 'بدء التنزيل فوراً' : 'Start downloading immediately',
                  style: const TextStyle(fontSize: 13),
                ),
                value: _startNow,
                onChanged: (val) => setState(() => _startNow = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isRtl ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton.icon(
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(
            isRtl ? 'إضافة (${urls.length})' : 'Add (${urls.length})',
          ),
          onPressed: (_isSubmitting || urls.isEmpty) ? null : _submit,
        ),
      ],
    );
  }
}
