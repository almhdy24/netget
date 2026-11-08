import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/download_task.dart';
import '../../services/download_manager.dart';
import '../../services/notification_permission_service.dart';

class AddDownloadSheet extends StatefulWidget {
  final DownloadManager manager;
  final String? initialUrl;
  final void Function(DownloadTask task)? onOpenExisting;
  final NotificationPermissionService? permissionService;

  const AddDownloadSheet({
    super.key,
    required this.manager,
    this.initialUrl,
    this.onOpenExisting,
    this.permissionService,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloadManager manager,
    String? initialUrl,
    void Function(DownloadTask task)? onOpenExisting,
    NotificationPermissionService? permissionService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddDownloadSheet(
        manager: manager,
        initialUrl: initialUrl,
        onOpenExisting: onOpenExisting,
        permissionService: permissionService,
      ),
    );
  }

  @override
  State<AddDownloadSheet> createState() => _AddDownloadSheetState();
}

class _AddDownloadSheetState extends State<AddDownloadSheet> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  late final TextEditingController _subFolderController;

  bool _isAutoName = true;
  bool _isAnalyzing = false;
  String? _errorText;
  bool _isSubmitting = false;

  // Analysis state
  UrlAnalysisResult? _analysis;
  DownloadCategory _selectedCategory = DownloadCategory.other;
  int _connections = 1;
  DownloadTask? _duplicateTask;
  bool _allowDuplicateDownload = false;

  @override
  void initState() {
    super.initState();
    final startUrl = widget.initialUrl?.trim() ?? '';
    _urlController = TextEditingController(text: startUrl);
    _nameController = TextEditingController();
    _subFolderController = TextEditingController();

    if (startUrl.isNotEmpty) {
      _nameController.text = NetGetUtils.extractFileNameFromUrl(startUrl);
      _selectedCategory = NetGetUtils.classifyCategory(_nameController.text);
      _subFolderController.text = _selectedCategory.folderName;
      _checkForDuplicateAndAnalyze(startUrl);
    }

    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    if (_isAutoName) {
      if (text.isNotEmpty) {
        final autoName = NetGetUtils.extractFileNameFromUrl(text);
        _nameController.text = autoName;
        _selectedCategory = NetGetUtils.classifyCategory(autoName);
        _subFolderController.text = _selectedCategory.folderName;
      } else {
        _nameController.clear();
      }
    }
    _duplicateTask = null;
    _allowDuplicateDownload = false;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _subFolderController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _urlController.text = text;
      _onUrlChanged();
      unawaited(_checkForDuplicateAndAnalyze(text));
    }
  }

  Future<void> _checkForDuplicateAndAnalyze(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;

    // Duplicate check
    final dup = widget.manager.findTaskByUrl(clean);
    if (dup != null && !_allowDuplicateDownload) {
      setState(() {
        _duplicateTask = dup;
      });
    }

    // Run quick link analysis
    setState(() {
      _isAnalyzing = true;
      _errorText = null;
    });

    try {
      final result = await widget.manager.analyzeUrl(clean);
      if (mounted) {
        setState(() {
          _analysis = result;
          _isAnalyzing = false;
          if (_isAutoName && result.fileName.isNotEmpty) {
            _nameController.text = result.fileName;
          }
          _selectedCategory = result.category;
          _subFolderController.text = result.category.folderName;
          if (!result.resumable) {
            _connections = 1;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _submit({required bool startNow}) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorText = 'Please enter a download URL');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      setState(
        () => _errorText = 'Only http:// and https:// URLs are supported',
      );
      return;
    }

    if (_duplicateTask != null && !_allowDuplicateDownload) {
      _showDuplicateDialog();
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    try {
      if (startNow && widget.permissionService != null) {
        await widget.permissionService!.maybePromptForDownload(context);
      }
      if (!mounted) return;

      final customName = _nameController.text.trim();
      final subFolder = _subFolderController.text.trim();

      await widget.manager.addDownload(
        url: url,
        customFileName: customName.isNotEmpty ? customName : null,
        startNow: startNow,
        category: _selectedCategory,
        connectionCount: _connections,
        subFolder: subFolder.isNotEmpty ? subFolder : null,
        totalBytes: _analysis?.totalBytes,
        resumable: _analysis?.resumable,
        etag: _analysis?.etag,
        lastModified: _analysis?.lastModified,
        source: widget.initialUrl != null ? 'clipboard' : 'link',
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              startNow ? 'Download started' : 'Added to queue (Download later)',
            ),
            duration: const Duration(seconds: 2),
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

  void _showDuplicateDialog() {
    final dup = _duplicateTask;
    if (dup == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.content_copy_rounded,
              color: Color(0xFFF57C00),
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Duplicate URL Detected'),
          ],
        ),
        content: Text(
          'This exact URL is already tracked as:\n"${dup.fileName}" (${dup.status.label}).\n\nWhat would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              widget.onOpenExisting?.call(dup);
            },
            child: const Text('Open Existing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _isAutoName = false;
                _nameController.text = 'copy_${_nameController.text}';
                _allowDuplicateDownload = true;
                _duplicateTask = null;
              });
            },
            child: const Text('Rename'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _allowDuplicateDownload = true;
                _duplicateTask = null;
              });
              _submit(startNow: true);
            },
            child: const Text('Download Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final bottomNavPadding = max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.padding.bottom,
    );
    final keyboardInset = mediaQuery.viewInsets.bottom;
    // Dynamic inset: when keyboard is shown, pad for keyboard; when hidden, pad for navigation bar
    final effectiveBottomPadding = keyboardInset > 0
        ? keyboardInset + 16.0
        : bottomNavPadding + 20.0;

    final analysis = _analysis;
    final sizeStr = analysis != null && analysis.totalBytes > 0
        ? NetGetUtils.formatBytes(analysis.totalBytes)
        : (analysis != null ? 'Unknown (Streaming)' : 'Analyzing...');

    final isResumable = analysis?.resumable ?? true;

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, effectiveBottomPadding),
      child: SingleChildScrollView(
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
                  color: isDark
                      ? const Color(0xFF383E46)
                      : const Color(0xFFD6DBE2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_link_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Download File Info',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAnalyzing) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Analyzing...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Duplicate warning banner if duplicate detected
            if (_duplicateTask != null && !_allowDuplicateDownload) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF57C00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFF57C00),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Duplicate link already in queue ("${_duplicateTask!.fileName}")',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _showDuplicateDialog,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Options'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // URL Input
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onSubmitted: (val) => _checkForDuplicateAndAnalyze(val),
              decoration: InputDecoration(
                labelText: 'Download URL',
                hintText: 'https://example.com/file.zip',
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Re-analyze',
                      onPressed: () =>
                          _checkForDuplicateAndAnalyze(_urlController.text),
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
                  ],
                ),
                errorText: _errorText,
              ),
            ),
            if (_urlController.text.isEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.content_paste_rounded, size: 14),
                  label: const Text(
                    'Paste from clipboard',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ],
            const SizedBox(height: 10),

            // File Name Input
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              onChanged: (text) {
                if (_isAutoName && text.isNotEmpty) {
                  _isAutoName = false;
                }
              },
              decoration: const InputDecoration(
                labelText: 'File Name',
                hintText: 'Auto-detected',
                prefixIcon: Icon(Icons.description_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            // Metadata card: Size, Resume support, Category
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14171A)
                    : const Color(0xFFF3F5F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF262B32)
                      : const Color(0xFFE2E6EC),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: _buildMetaChip(
                          context,
                          label: 'Size',
                          value: sizeStr,
                          icon: Icons.data_usage_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: _buildResumeChip(context, isResumable)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.folder_outlined,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Category:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DownloadCategory>(
                            value: _selectedCategory,
                            isDense: true,
                            isExpanded: true,
                            iconSize: 18,
                            items: DownloadCategory.values
                                .where((c) => c != DownloadCategory.all)
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          NetGetUtils.getCategoryIcon(cat),
                                          size: 15,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            cat.label,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (cat) {
                              if (cat != null) {
                                setState(() {
                                  _selectedCategory = cat;
                                  _subFolderController.text = cat.folderName;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Save to folder field
            TextField(
              controller: _subFolderController,
              decoration: const InputDecoration(
                labelText: 'Save Subfolder',
                hintText: 'e.g. Video, Documents, ISO',
                prefixIcon: Icon(Icons.create_new_folder_outlined, size: 20),
                helperText: 'Saved inside public Downloads/NetGet folder',
              ),
            ),
            const SizedBox(height: 12),

            // Connections selector (1/2/4, default 1)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Connections (multi-connection beta):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _connections == 1
                          ? '1 connection'
                          : '$_connections connections',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 (Standard)')),
                      ButtonSegment(value: 2, label: Text('2 (Beta)')),
                      ButtonSegment(value: 4, label: Text('4 (Beta)')),
                    ],
                    selected: {_connections},
                    onSelectionChanged: isResumable
                        ? (sel) => setState(() => _connections = sel.first)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons: [Download later] [Start now]
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _submit(startNow: false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Download later'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _submit(startNow: true),
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
                    label: const Text('Start now'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResumeChip(BuildContext context, bool isResumable) {
    final statusColors = Theme.of(context).statusColors;
    final color = isResumable ? statusColors.completed : statusColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isResumable
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isResumable ? 'Resume Supported' : 'No Range / Single Stream',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
