import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/qr_provider.dart';

/// 识别 Tab:选择图片 / 拖拽图片 → 解码二维码内容 → 复制/分享。
class QrRecognizeTab extends StatefulWidget {
  const QrRecognizeTab({super.key});

  @override
  State<QrRecognizeTab> createState() => _QrRecognizeTabState();
}

class _QrRecognizeTabState extends State<QrRecognizeTab> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Consumer<QrProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 选图 / 拖拽区
              DropTarget(
                onDragEntered: (_) => setState(() => _isDragOver = true),
                onDragExited: (_) => setState(() => _isDragOver = false),
                onDragDone: (details) {
                  setState(() => _isDragOver = false);
                  if (details.files.isNotEmpty) {
                    _decodePath(context, provider, details.files.first.path);
                  }
                },
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickImage(context, provider),
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: _isDragOver
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDragOver
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isDragOver
                              ? Icons.file_download_done
                              : Icons.qr_code_scanner,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(loc.qrPickImage),
                        const SizedBox(height: 4),
                        Text(
                          loc.qrDragHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 解码状态
              if (provider.isDecoding)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (provider.lastDecoded != null)
                _buildResultPanel(context, provider, loc)
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      loc.qrNoResult,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResultPanel(
    BuildContext context,
    QrProvider provider,
    AppLocalizations loc,
  ) {
    final text = provider.lastDecoded!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.qrDecodeResult,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: loc.copy,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(loc.copiedToClipboard)),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: loc.share,
                onPressed: () => Share.share(text),
              ),
            ],
          ),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (provider.lastDecodedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${loc.qrDecodeTime} ${_formatTime(provider.lastDecodedAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  /// 格式化识别时间为 "yyyy-MM-dd HH:mm:ss"。
  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _pickImage(BuildContext context, QrProvider provider) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path != null) {
      await _decodePath(context, provider, file.path!);
    } else if (file.bytes != null) {
      try {
        await provider.decodeImage(file.bytes!);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context).qrDecodeFailed}: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _decodePath(
    BuildContext context,
    QrProvider provider,
    String path,
  ) async {
    try {
      // File.readAsBytes 是异步 IO,不阻塞 UI 线程。
      final bytes = await File(path).readAsBytes();
      if (!context.mounted) return;
      await provider.decodeImage(bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).qrDecodeFailed}: $e')),
        );
      }
    }
  }
}
