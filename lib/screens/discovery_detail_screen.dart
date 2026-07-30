import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/discovery_item.dart';
import '../widgets/custom_title_bar.dart';

class DiscoveryDetailScreen extends StatelessWidget {
  final DiscoveryItem item;

  const DiscoveryDetailScreen({super.key, required this.item});

  Future<void> _onShare(BuildContext context) async {
    await Share.share(
      '${item.name}\n${item.description}\n${item.url}',
      subject: item.name,
    );
  }

  Future<void> _onOpenUrl(BuildContext context) async {
    final uri = Uri.parse(item.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDesktop = CustomTitleBar.isDesktop;
    final horizontalPadding = isDesktop ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: loc.discoveryShare,
            onPressed: () => _onShare(context),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: loc.discoveryOpenBrowser,
            onPressed: () => _onOpenUrl(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner image (bannerUrl first, fallback to iconUrl)
            if (item.bannerUrl != null && item.bannerUrl!.isNotEmpty)
              ClipRRect(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Image.network(
                      item.bannerUrl!,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => item.iconUrl != null && item.iconUrl!.isNotEmpty
                          ? Image.network(
                              item.iconUrl!,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildPlaceholderIcon(theme),
                            )
                          : _buildPlaceholderIcon(theme),
                    ),
                  ),
                ),
              )
            else if (item.iconUrl != null && item.iconUrl!.isNotEmpty)
              ClipRRect(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Image.network(
                      item.iconUrl!,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _buildPlaceholderIcon(theme),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _buildPlaceholderIcon(theme),
              ),

            SizedBox(height: isDesktop ? 24 : 20),

            // Content: Name, description, tags
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + icon + type badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (item.iconUrl != null && item.iconUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            item.iconUrl!,
                            width: isDesktop ? 60 : 52,
                            height: isDesktop ? 60 : 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            loadingBuilder: (_, child, loadingProgress) =>
                                loadingProgress == null ? child : const SizedBox(
                              width: 52,
                              height: 52,
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Text(
                          item.name,
                          style: (isDesktop
                              ? theme.textTheme.headlineSmall
                              : theme.textTheme.titleLarge
                          )?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildTypeBadge(context, theme),
                    ],
                  ),

                  // Description
                  if (item.description.isNotEmpty) ...[
                    SizedBox(height: isDesktop ? 16 : 14),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isDesktop ? 16 : 14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.7,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],

                  // Tags
                  if (item.tagList.isNotEmpty) ...[
                    SizedBox(height: isDesktop ? 20 : 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.tagList.map((tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: isDesktop ? 20 : 16),

            // Divider
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.15)),
            ),

            SizedBox(height: isDesktop ? 16 : 14),

            // URL metadata card
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(isDesktop ? 18 : 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // URL row with copy
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            item.url,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: item.url));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(loc.discoveryCopied),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: isDesktop ? 32 : 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderIcon(ThemeData theme) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Icon(
          Icons.explore,
          size: 80,
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(BuildContext context, ThemeData theme) {
    final loc = AppLocalizations.of(context);
    final color = _typeColor(item.type, theme);
    final label = _typeName(item.type, loc);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _typeColor(int type, ThemeData theme) {
    final scheme = theme.colorScheme;
    switch (type) {
      case 0:
        return scheme.primary;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.red;
      default:
        return scheme.outline;
    }
  }

  String _typeName(int type, AppLocalizations loc) {
    switch (type) {
      case 0:
        return loc.discoveryTypeOfficial;
      case 1:
        return loc.discoveryTypeRecommended;
      case 2:
        return loc.discoveryTypeAd;
      default:
        return '';
    }
  }
}
