import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/linux_command.dart';
import '../providers/linux_command_provider.dart';
import '../widgets/custom_title_bar.dart';

class LinuxCommandsScreen extends StatefulWidget {
  const LinuxCommandsScreen({super.key});

  @override
  State<LinuxCommandsScreen> createState() => _LinuxCommandsScreenState();
}

class _LinuxCommandsScreenState extends State<LinuxCommandsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LinuxCommandProvider>().loadCommands(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final provider = context.read<LinuxCommandProvider>();
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !provider.isLoading &&
        provider.hasMore) {
      provider.loadCommands();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(loc.linuxCommands),
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(title: loc.linuxCommands, showBackButton: true),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: loc.search,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          context.read<LinuxCommandProvider>().searchCommands('');
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                context.read<LinuxCommandProvider>().searchCommands(v);
              },
            ),
          ),
          Consumer<LinuxCommandProvider>(
            builder: (ctx, provider, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      loc.totalCommands.replaceAll('{count}', '${provider.totalCount}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<LinuxCommandProvider>(
              builder: (ctx, provider, _) {
                if (provider.commands.isEmpty && !provider.isLoading) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal,
                            size: 64, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(loc.noCommands,
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: provider.commands.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == provider.commands.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final cmd = provider.commands[i];
                    return _buildCommandTile(context, cmd);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandTile(BuildContext context, LinuxCommand cmd) {
    final loc = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            cmd.command,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          cmd.descriptionZh,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                cmd.descriptionEn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (cmd.examples.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${cmd.examples.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: loc.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cmd.command));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc.commandCopied),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
        onTap: () => _showDetail(context, cmd),
      ),
    );
  }

  void _showDetail(BuildContext context, LinuxCommand cmd) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cmd.command, style: const TextStyle(fontFamily: 'monospace')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cmd.descriptionZh,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                cmd.descriptionEn,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (cmd.examples.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).usageExamples,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...cmd.examples.map((ex) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          ex.example,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (ex.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            ex.note,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: cmd.command));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).commandCopied),
                  duration: const Duration(seconds: 1),
                ),
              );
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(context).copy),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).confirm),
          ),
        ],
      ),
    );
  }
}
