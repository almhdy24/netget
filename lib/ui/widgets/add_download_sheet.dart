import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils.dart';
import '../../services/download_manager.dart';

class AddDownloadSheet extends StatefulWidget {
  final DownloadManager manager;
  final String? initialUrl;

  const AddDownloadSheet({
    super.key,
    required this.manager,
    this.initialUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloadManager manager,
    String? initialUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddDownloadSheet(
        manager: manager,
        initialUrl: initialUrl,
      ),
    );
  }

  @override
  State<AddDownloadSheet> createState() => _AddDownloadSheetState();
}

class _AddDownloadSheetState extends State<AddDownloadSheet> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  bool _isAutoName = true;
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    _nameController = TextEditingController();

    if (_urlController.text.isNotEmpty) {
      _nameController.text =
          NetGetUtils.extractFileNameFromUrl(_urlController.text);
    }

    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    if (_isAutoName) {
      final text = _urlController.text.trim();
      if (text.isNotEmpty) {
        _nameController.text = NetGetUtils.extractFileNameFromUrl(text);
      } else {
        _nameController.clear();
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _urlController.text = text;
      _onUrlChanged();
    }
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorText = 'Please enter a download URL');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      setState(() => _errorText = 'Only http:// and https:// URLs are supported');
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    try {
      final customName = _nameController.text.trim();
      await widget.manager.addDownload(
        url: url,
        customFileName: customName.isNotEmpty ? customName : null,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download started'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorText = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1E22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF383E46) : const Color(0xFFD6DBE2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'New Download',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // URL Input
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Download URL',
              hintText: 'https://example.com/file.zip',
              prefixIcon: const Icon(Icons.link_rounded, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                tooltip: 'Paste from clipboard',
                onPressed: _pasteFromClipboard,
              ),
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 12),

          // File Name Input
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (text) {
              if (_isAutoName && text.isNotEmpty) {
                _isAutoName = false;
              }
            },
            decoration: InputDecoration(
              labelText: 'File Name',
              hintText: 'Auto-detected from URL',
              prefixIcon: const Icon(Icons.description_outlined, size: 20),
              helperText: 'Saved to device Downloads folder',
            ),
          ),
          const SizedBox(height: 20),

          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('Start Download'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
