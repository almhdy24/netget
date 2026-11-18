import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/utils.dart';
import '../../models/download_task.dart';
import '../../services/nearby_share_service.dart';

class NearbyShareSheet extends StatefulWidget {
  final DownloadTask task;
  final NearbyShareService? customService;
  final String? explicitIp;
  final String? initialShareUrl;

  const NearbyShareSheet({
    super.key,
    required this.task,
    this.customService,
    this.explicitIp,
    this.initialShareUrl,
  });

  static Future<void> show(BuildContext context, DownloadTask task) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NearbyShareSheet(task: task),
    );
  }

  @override
  State<NearbyShareSheet> createState() => _NearbyShareSheetState();
}

class _NearbyShareSheetState extends State<NearbyShareSheet> {
  late final NearbyShareService _service;
  bool _ownsService = false;
  bool _isStarting = true;
  String? _shareUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.customService != null) {
      _service = widget.customService!;
      _ownsService = false;
    } else {
      _service = NearbyShareService();
      _ownsService = true;
    }
    if (widget.initialShareUrl != null) {
      _shareUrl = widget.initialShareUrl;
      _isStarting = false;
    } else {
      _startSharing();
    }
  }

  Future<void> _startSharing() async {
    try {
      final file = File(widget.task.savePath);
      final url = await _service.startSharing(
        file,
        customFileName: widget.task.fileName,
        explicitIp: widget.explicitIp,
      );
      if (mounted) {
        setState(() {
          _shareUrl = url;
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isStarting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.stopSharing();
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle drag bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_tethering_rounded,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isRtl
                        ? 'شارك بالقرب (بدون إنترنت)'
                        : 'Nearby Share (Offline)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.task.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),

              if (_isStarting) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(),
                ),
              ] else if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Error starting local share: $_error',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ] else if (_shareUrl != null) ...[
                // QR Code
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _shareUrl!,
                    version: QrVersions.auto,
                    size: 200.0,
                    gapless: false,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1E293B),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Share URL Box with Copy Button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _shareUrl!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: isRtl ? 'نسخ الرابط' : 'Copy URL',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _shareUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isRtl
                                    ? 'تم نسخ الرابط إلى الحافظة'
                                    : 'Share link copied',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Instructions in Sudanese Arabic / English
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isRtl
                              ? '1. افتح نقطة الاتصال (Hotspot) أو اتصلوا بنفس الواي-فاي.\n'
                                    '2. امسح رمز الـ QR من الكاميرا أو الصق الرابط في المتصفح أو NetGet.\n'
                                    '3. التحميل بسرعة الواي-فاي وبدون استهلاك للبيانات!'
                              : '1. Connect both devices to the same Wi-Fi or Hotspot.\n'
                                    '2. Scan this QR code or paste URL in browser / NetGet.\n'
                                    '3. Transfers locally at Wi-Fi speeds without data usage!',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Real-time transfer stats stream
                StreamBuilder<NearbyShareUpdate>(
                  stream: _service.updates,
                  builder: (context, snapshot) {
                    final update = snapshot.data;
                    final peers = update?.activePeers ?? _service.activePeers;
                    final transferred =
                        update?.transferredBytes ?? _service.transferredBytes;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            context,
                            icon: Icons.devices_rounded,
                            label: isRtl
                                ? 'الأجهزة المتصلة'
                                : 'Connected Peers',
                            value: '$peers',
                            color: peers > 0
                                ? Colors.green
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          Container(
                            width: 1,
                            height: 30,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          _buildStatItem(
                            context,
                            icon: Icons.arrow_upward_rounded,
                            label: isRtl ? 'المنقول' : 'Transferred',
                            value: NetGetUtils.formatBytes(transferred),
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Done / Stop button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(isRtl ? 'إغلاق المشاركة' : 'Stop Sharing'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
