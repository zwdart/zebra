import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../l10n/app_localizations.dart';

class UpdateDialog extends StatefulWidget {
  final bool showSkip;
  final bool isManualCheck;

  const UpdateDialog({
    super.key,
    this.showSkip = true,
    this.isManualCheck = false,
  });

  static Future<void> showIfNeeded(BuildContext context) async {
    final provider = context.read<UpdateProvider>();
    await provider.silentCheck();
    if (provider.state == UpdateState.hasUpdate && context.mounted) {
      // 检查是否在跳过期内
      final isSkipValid = await UpdateService.isSkipUpdateValid();
      if (!isSkipValid) {
        showDialog(
          context: context,
          barrierDismissible: !provider.forceUpdate,
          builder: (_) => const UpdateDialog(showSkip: true),
        );
      }
    }
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    if (widget.isManualCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<UpdateProvider>().checkForUpdate();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<UpdateProvider>(
      builder: (context, provider, _) {
        // 检查中
        if (provider.state == UpdateState.checking) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(loc.checkingForUpdate),
              ],
            ),
          );
        }

        // 错误
        if (provider.state == UpdateState.error) {
          return AlertDialog(
            icon: Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            title: Text(loc.updateCheckFailed),
            content: Text(provider.errorMessage ?? loc.unknownError),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.cancel),
              ),
              if (!widget.isManualCheck)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    provider.checkForUpdate();
                  },
                  child: Text(loc.retry),
                ),
            ],
          );
        }

        // 无更新
        if (provider.state == UpdateState.noUpdate) {
          return AlertDialog(
            icon: Icon(Icons.check_circle, color: colorScheme.primary, size: 48),
            title: Text(loc.noUpdatesAvailable),
            content: Text(loc.currentVersionIsLatest),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.confirm),
              ),
            ],
          );
        }

        // 下载中
        if (provider.state == UpdateState.downloading) {
          final progress = provider.progress;
          return AlertDialog(
            title: Text(loc.downloadingUpdate),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress?.percent,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 12),
                if (progress != null)
                  Text(
                    '${UpdateService.formatFileSize(progress.received)} / ${UpdateService.formatFileSize(progress.total)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          );
        }

        // 下载完成
        if (provider.state == UpdateState.downloadComplete) {
          final filePath = provider.downloadedFilePath ?? '';
          return AlertDialog(
            icon: Icon(Icons.download_done, color: colorScheme.primary, size: 48),
            title: Text(loc.downloadComplete),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.downloadCompleteMsg),
                const SizedBox(height: 16),
                Text(
                  loc.downloadPathLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          filePath,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: loc.copyPath,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: filePath));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(loc.pathCopied),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.cancel),
              ),
              TextButton(
                onPressed: () {
                  provider.openDownloadFolder();
                },
                child: Text(loc.openFolder),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  provider.openDownloadedFile();
                },
                child: Text(loc.installNow),
              ),
            ],
          );
        }

        // 有更新（默认）
        final info = provider.versionInfo;
        if (info == null) return const SizedBox.shrink();

        return AlertDialog(
          icon: Icon(
            provider.forceUpdate ? Icons.system_update : Icons.update,
            color: provider.forceUpdate ? colorScheme.error : colorScheme.primary,
            size: 48,
          ),
          title: Text(provider.forceUpdate ? loc.forceUpdateRequired : loc.newVersionAvailable),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 版本信息
                _buildInfoRow(context, loc.version, info.version),
                _buildInfoRow(context, loc.releaseDate, info.releaseDate),
                if (info.fileSize > 0)
                  _buildInfoRow(
                    context,
                    loc.fileSize,
                    UpdateService.formatFileSize(info.fileSize),
                  ),
                const SizedBox(height: 12),
                // 更新日志
                Text(
                  loc.changelog,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    info.changelog,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                // 强制更新提示
                if (provider.forceUpdate) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: colorScheme.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.forceUpdateMessage,
                            style: TextStyle(color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // 跳过按钮（非强制更新时显示）
            if (widget.showSkip && !provider.forceUpdate)
              TextButton(
                onPressed: () {
                  UpdateService.saveSkipUpdateTime();
                  Navigator.pop(context);
                },
                child: Text(loc.skip),
              ),
            // 更新按钮 - 根据类型显示不同文案
            if (info.isUrlType)
              FilledButton(
                onPressed: () {
                  // Navigator.pop(context);
                  provider.openExternalUrl();
                },
                child: Text(loc.openLink),
              )
            else if (Platform.isAndroid || Platform.isIOS)
              FilledButton(
                onPressed: () {
                  // Navigator.pop(context);
                  provider.openStore();
                },
                child: Text(loc.updateNow),
              )
            else
              FilledButton(
                onPressed: () {
                  // Navigator.pop(context);
                  provider.downloadUpdate();
                },
                child: Text(loc.downloadNow),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
