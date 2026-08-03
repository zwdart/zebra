import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/zebra_paths.dart';
import '../models/qr_style_config.dart';
import '../providers/qr_provider.dart';

/// 生成 Tab:内容输入 + 预览 + 样式设置(简单/高级)+ 保存/分享。
class QrGenerateTab extends StatefulWidget {
  const QrGenerateTab({super.key});

  @override
  State<QrGenerateTab> createState() => _QrGenerateTabState();
}

class _QrGenerateTabState extends State<QrGenerateTab> {
  static const _presetColors = <Color>[
    Color(0xFF000000),
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFF7B1FA2),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF00695C),
    Color(0xFF37474F),
  ];

  /// 输入框控制器:必须持久化,不能每次 build 重建。
  ///
  /// 之前每次 build 都新建 controller,导致每次按键触发 provider 通知重建后,
  /// TextField 拿到全新 controller,光标位置被重置、IME 组合输入被打断,
  /// 在 Linux 上表现为输入内容跳跃乱显示。
  final TextEditingController _contentController = TextEditingController(text: '');

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Consumer<QrProvider>(
      builder: (context, provider, _) {
        final config = provider.config;
        // 内容被外部重置(如切换 Tab 后 State 重建)时同步回输入框;
        // 输入过程中 controller 与 config.data 由 onChanged 保持同步,不会触发。
        // 延迟到帧末执行,避免 build 期间改 controller 触发 markNeedsBuild 异常。
        if (_contentController.text != config.data) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _contentController.text != provider.config.data) {
              _contentController.text = provider.config.data;
            }
          });
        }
        final qrImage = provider.buildPreviewImage();
        final decoration = provider.buildDecoration();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _contentController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: loc.qrContent,
                  hintText: loc.qrContentHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    provider.updateConfigField((c) => c.copyWith(data: v)),
              ),
              const SizedBox(height: 16),
              // 预览区
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: config.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: config.data.isEmpty
                        ? Center(
                            child: Text(
                              loc.qrContentHint,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline,
                              ),
                            ),
                          )
                        : PrettyQrView(
                            qrImage: qrImage,
                            decoration: decoration,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: config.data.isEmpty
                          ? null
                          : () => _saveImage(context, provider, loc),
                      icon: const Icon(Icons.save_alt),
                      label: Text(loc.qrSave),
                    ),
                    OutlinedButton.icon(
                      onPressed: config.data.isEmpty
                          ? null
                          : () => _shareImage(context, provider, loc),
                      icon: const Icon(Icons.share),
                      label: Text(loc.qrShare),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              _buildSectionHeader(context, loc.qrBasicSettings),
              // 容错级别
              _buildLabel(context, loc.qrErrorLevel),
              Wrap(
                spacing: 8,
                children: [
                  for (final level in QrErrorLevel.values)
                    ChoiceChip(
                      label: Text(_errorLevelName(loc, level)),
                      selected: config.errorLevel == level,
                      // 带 logo 时低纠错会被生成器强制提升到 Q,禁用以免误解
                      onSelected: config.logoBytes != null &&
                              level.index < QrErrorLevel.quartile.index
                          ? null
                          : (_) => provider.updateConfigField(
                              (c) => c.copyWith(errorLevel: level)),
                    ),
                ],
              ),
              if (config.logoBytes != null) ...[
                const SizedBox(height: 4),
                Text(
                  loc.qrLogoErrorLevelHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // 前景/背景颜色
              Row(
                children: [
                  _buildColorPicker(
                    context,
                    label: loc.qrForeground,
                    color: config.fgColor,
                    onChanged: (c) =>
                        provider.updateConfigField((cfg) => cfg.copyWith(fgColor: c)),
                  ),
                  const SizedBox(width: 24),
                  _buildColorPicker(
                    context,
                    label: loc.qrBackground,
                    color: config.bgColor,
                    onChanged: (c) =>
                        provider.updateConfigField((cfg) => cfg.copyWith(bgColor: c)),
                  ),
                ],
              ),
              // 自定义颜色
              if (config.useCustomColor)
                Row(
                  children: [
                    _buildColorPicker(
                      context,
                      label: loc.qrCustomColor,
                      color: config.customColor ?? config.fgColor,
                      onChanged: (c) =>
                          provider.updateConfigField((cfg) => cfg.copyWith(
                              customColor: c,
                              useCustomColor: true)),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      loc.qrCustomColorDesc,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              const Divider(height: 32),
              _buildSectionHeader(context, loc.qrAdvancedSettings),
              // 形状
              _buildLabel(context, loc.qrShape),
              Wrap(
                spacing: 8,
                children: [
                  for (final shape in QrShapeStyle.values)
                    ChoiceChip(
                      label: Text(_shapeName(loc, shape)),
                      selected: config.shape == shape,
                      onSelected: (_) => provider.updateConfigField(
                          (c) => c.copyWith(shape: shape)),
                    ),
                ],
              ),
              // 渐变
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(loc.qrGradient),
                value: config.useGradient,
                onChanged: (v) => provider
                    .updateConfigField((c) => c.copyWith(useGradient: v)),
              ),
              if (config.useGradient)
                Row(
                  children: [
                    _buildColorPicker(
                      context,
                      label: loc.qrGradientStart,
                      color: config.gradientColors.isNotEmpty
                          ? config.gradientColors.first
                          : config.fgColor,
                      onChanged: (c) =>
                          provider.updateConfigField((cfg) => cfg.copyWith(
                              gradientColors: [c, cfg.gradientColors.last])),
                    ),
                    const SizedBox(width: 24),
                    _buildColorPicker(
                      context,
                      label: loc.qrGradientEnd,
                      color: config.gradientColors.length > 1
                          ? config.gradientColors.last
                          : config.fgColor,
                      onChanged: (c) =>
                          provider.updateConfigField((cfg) => cfg.copyWith(
                              gradientColors: [cfg.gradientColors.first, c])),
                    ),
                  ],
                ),
              // 静区
              _buildSlider(
                context,
                label: loc.qrQuietZone,
                value: config.quietZone.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                onChanged: (v) => provider.updateConfigField(
                    (c) => c.copyWith(quietZone: v.round())),
              ),
              // 密度
              _buildSlider(
                context,
                label: loc.qrDensity,
                value: config.density,
                min: 0.3,
                max: 1.0,
                divisions: 7,
                onChanged: (v) => provider
                    .updateConfigField((c) => c.copyWith(density: v)),
              ),
              // 圆角(仅 squares 形状)
              if (config.shape == QrShapeStyle.squares)
                _buildSlider(
                  context,
                  label: loc.qrRounding,
                  value: config.rounding,
                  min: 0,
                  max: 1.0,
                  divisions: 10,
                  onChanged: (v) => provider
                      .updateConfigField((c) => c.copyWith(rounding: v)),
                ),
              // Logo
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: Text(loc.qrLogo),
                subtitle: Text(
                  config.logoBytes == null ? loc.qrNoLogo : loc.qrLogoSet,
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      tooltip: loc.qrPickLogo,
                      onPressed: () => _pickLogo(context, provider),
                    ),
                    if (config.logoBytes != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: loc.qrRemoveLogo,
                        onPressed: () => provider
                            .updateConfigField((c) => c.copyWith(logoBytes: null)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  Widget _buildColorPicker(
    BuildContext context, {
    required String label,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showColorPickerDialog(context, label, color, onChanged),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showColorPickerDialog(
    BuildContext context,
    String title,
    Color current,
    ValueChanged<Color> onChanged,
  ) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in _presetColors)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.pop(ctx, color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == current
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.outline,
                      width: color == current ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
        ],
      ),
    );
    if (selected != null) onChanged(selected);
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Future<void> _pickLogo(BuildContext context, QrProvider provider) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    final bytes = await File(file.path!).readAsBytes();
    provider.updateConfigField((c) => c.copyWith(logoBytes: bytes));
  }

  Future<void> _saveImage(
    BuildContext context,
    QrProvider provider,
    AppLocalizations loc,
  ) async {
    try {
      final bytes = await provider.exportPng();
      if (Platform.isAndroid || Platform.isIOS) {
        // 移动端保存到系统相册
        await Gal.putImageBytes(bytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.qrSavedToGallery)),
          );
        }
        return;
      }
      // 桌面端保存到应用文档目录
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final path = await ZebraPaths.filePath('qr', 'qr_$ts.png');
      await File(path).writeAsBytes(bytes);
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.qrSave),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.qrSaveSuccess),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  path,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.close),
            ),
            FilledButton(
              onPressed: () {
                Share.shareXFiles([XFile(path)], subject: 'qr_$ts.png');
                Navigator.pop(ctx);
              },
              child: Text(loc.share),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.qrSaveFailed}: $e')),
        );
      }
    }
  }

  Future<void> _shareImage(
    BuildContext context,
    QrProvider provider,
    AppLocalizations loc,
  ) async {
    try {
      final bytes = await provider.exportPng();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: 'qr_$ts.png',
          ),
        ],
        subject: 'qr_$ts.png',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.qrShareFailed}: $e')),
        );
      }
    }
  }

  String _errorLevelName(AppLocalizations loc, QrErrorLevel level) {
    switch (level) {
      case QrErrorLevel.low:
        return loc.qrErrorLevelLow;
      case QrErrorLevel.medium:
        return loc.qrErrorLevelMedium;
      case QrErrorLevel.quartile:
        return loc.qrErrorLevelQuartile;
      case QrErrorLevel.high:
        return loc.qrErrorLevelHigh;
    }
  }

  String _shapeName(AppLocalizations loc, QrShapeStyle shape) {
    switch (shape) {
      case QrShapeStyle.squares:
        return loc.qrShapeSquares;
      case QrShapeStyle.smooth:
        return loc.qrShapeSmooth;
      case QrShapeStyle.dots:
        return loc.qrShapeDots;
      case QrShapeStyle.rounded:
        return loc.qrShapeRounded;
    }
  }
}