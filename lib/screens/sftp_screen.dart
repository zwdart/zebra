import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../providers/sftp_provider.dart';
import '../providers/ssh_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/progress_dialog.dart';
import '../models/sftp_file_item.dart';

class SftpScreen extends StatefulWidget {
  const SftpScreen({super.key});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

enum SortField { name, size, modified }
enum SortOrder { asc, desc }

class _SftpScreenState extends State<SftpScreen> {
  bool _isDragOver = false;
  bool _showRawValues = true;
  SortField _sortField = SortField.name;
  SortOrder _sortOrder = SortOrder.asc;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSftp();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SftpFileItem> _getFilteredFiles(SftpProvider sftpProvider) {
    final query = _searchController.text.toLowerCase();
    final list = query.isEmpty
        ? List<SftpFileItem>.from(sftpProvider.files)
        : sftpProvider.files.where((file) {
            return file.name.toLowerCase().contains(query);
          }).toList();
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortField.size:
          cmp = a.size.compareTo(b.size);
        case SortField.modified:
          cmp = a.modifiedAt.compareTo(b.modifiedAt);
      }
      return _sortOrder == SortOrder.asc ? cmp : -cmp;
    });
    return list;
  }

  void _showSortMenu(BuildContext context) {
    final loc = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(loc.sortBy, style: Theme.of(context).textTheme.titleMedium),
            ),
            _buildSortOption(ctx, loc.sortByName, SortField.name),
            _buildSortOption(ctx, loc.sortBySize, SortField.size),
            _buildSortOption(ctx, loc.sortByDate, SortField.modified),
            const Divider(),
            ListTile(
              leading: Icon(_sortOrder == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward),
              title: Text(_sortOrder == SortOrder.asc ? loc.ascending : loc.descending),
              onTap: () {
                setState(() {
                  _sortOrder = _sortOrder == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(BuildContext ctx, String label, SortField field) {
    return ListTile(
      leading: Icon(_sortField == field ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(label),
      onTap: () {
        setState(() => _sortField = field);
        Navigator.pop(ctx);
      },
    );
  }

  Future<void> _initSftp() async {
    final sshProvider = context.read<SshProvider>();
    final sftpProvider = context.read<SftpProvider>();
    try {
      await sftpProvider.attachToSsh(sshProvider.sshService);
      await sftpProvider.listDirectory('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SFTP error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final sftpProvider = context.watch<SftpProvider>();
    final filteredFiles = _getFilteredFiles(sftpProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(sftpProvider.currentPath),
        leading: sftpProvider.canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => sftpProvider.goBack(),
              )
            : null,
        actions: [
          if (sftpProvider.isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: loc.selectAll,
              onPressed: sftpProvider.selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: loc.deselectAll,
              onPressed: sftpProvider.clearSelection,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: loc.delete,
              onPressed: () => _deleteSelected(context),
            ),
            IconButton(
              icon: const Icon(Icons.archive),
              tooltip: loc.compress,
              onPressed: () => _compressSelected(context),
            ),
          ] else ...[
            IconButton(
              icon: Icon(_showRawValues ? Icons.auto_awesome : Icons.code),
              tooltip: _showRawValues ? loc.showConverted : loc.showRaw,
              onPressed: () => setState(() => _showRawValues = !_showRawValues),
            ),
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: loc.sort,
              onPressed: () => _showSortMenu(context),
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              tooltip: loc.newFolder,
              onPressed: () => _createFolder(context),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: loc.upload,
              onPressed: () => _uploadFiles(context),
            ),
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: loc.openTerminalHere,
              onPressed: () => _openTerminalHere(context),
            ),
            IconButton(
              icon: const Icon(Icons.folder_special),
              tooltip: loc.navigateToPath,
              onPressed: () => _navigateToPath(context),
            ),
          ],
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        onDragDone: (details) async {
          setState(() => _isDragOver = false);
          await _handleDroppedFiles(details.files);
        },
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: loc.searchFiles,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: sftpProvider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : sftpProvider.error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                  const SizedBox(height: 16),
                                  Text(sftpProvider.error!),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => sftpProvider.listDirectory(),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => sftpProvider.listDirectory(),
                              child: filteredFiles.isEmpty
                                  ? Center(child: Text(loc.search))
                                  : ListView.builder(
                                      itemCount: filteredFiles.length,
                                      itemBuilder: (ctx, i) {
                                        final file = filteredFiles[i];
                                        final isSelected =
                                            sftpProvider.selectedFiles.contains(file.path);
                                        return FileListTile(
                                          file: file,
                                          isSelected: isSelected,
                                          showRawValues: _showRawValues,
                                          onTap: () {
                                            if (sftpProvider.isSelectionMode) {
                                              sftpProvider.toggleSelection(file.path);
                                            } else if (file.isDirectory) {
                                              sftpProvider.navigateTo(file.path);
                                            } else {
                                              _downloadFile(context, file.path);
                                            }
                                          },
                                          onLongPress: () {
                                            sftpProvider.toggleSelection(file.path);
                                          },
                                          trailing: PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, size: 20),
                                            onSelected: (value) =>
                                                _handleMenuAction(context, value, file),
                                            itemBuilder: (ctx) => [
                                              if (!file.isDirectory)
                                                PopupMenuItem(
                                                  value: 'view',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.visibility, size: 20),
                                                      const SizedBox(width: 8),
                                                      Text(loc.viewFile),
                                                    ],
                                                  ),
                                                ),
                                              if (!file.isDirectory)
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.edit, size: 20),
                                                      const SizedBox(width: 8),
                                                      Text(loc.editFile),
                                                    ],
                                                  ),
                                                ),
                                              if (file.isDirectory)
                                                PopupMenuItem(
                                                  value: 'terminal',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.terminal, size: 20),
                                                      const SizedBox(width: 8),
                                                      Text(loc.openTerminalHere),
                                                    ],
                                                  ),
                                                ),
                                              PopupMenuItem(
                                                value: 'download',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.download, size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.download),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.delete,
                                                        size: 20, color: Colors.red),
                                                    const SizedBox(width: 8),
                                                    Text(loc.delete,
                                                        style: const TextStyle(
                                                            color: Colors.red)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuDivider(),
                                              PopupMenuItem(
                                                value: 'copyPath',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.copy, size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.copyPath),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                ),
              ],
            ),
            if (_isDragOver)
              Container(
                color: Theme.of(context).colorScheme.primary.withAlpha(30),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_upload,
                          size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(loc.dragFilesHere,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _uploadFiles(context),
        child: const Icon(Icons.upload),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action, SftpFileItem file) {
    final loc = AppLocalizations.of(context);
    switch (action) {
      case 'view':
        _downloadFile(context, file.path);
        break;
      case 'edit':
        _editFile(context, file.path);
        break;
      case 'terminal':
        _openTerminalHere(context);
        break;
      case 'download':
        _downloadFile(context, file.path);
        break;
      case 'delete':
        _deleteFile(context, file.path);
        break;
      case 'copyPath':
        Clipboard.setData(ClipboardData(text: file.path));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.pathCopied}')),
          );
        }
        break;
    }
  }

  void _openTerminalHere(BuildContext context) {
    Navigator.pushNamed(context, '/terminal');
  }

  void _navigateToPath(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.navigateToPath),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: loc.enterPath,
            prefixIcon: const Icon(Icons.folder),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                context.read<SftpProvider>().navigateTo(path);
              }
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _editFile(BuildContext context, String remotePath) async {
    final sftpProvider = context.read<SftpProvider>();
    final loc = AppLocalizations.of(context);

    try {
      final content = await sftpProvider.sftpService.readFileContent(remotePath);
      if (content == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot read file')),
          );
        }
        return;
      }

      final controller = TextEditingController(text: content);
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${loc.editFile} - ${p.basename(remotePath)}'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(loc.save),
            ),
          ],
        ),
      );

      if (result != null && result != content) {
        await sftpProvider.sftpService.writeFileContent(remotePath, result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.basename(remotePath)} saved')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleDroppedFiles(List<DropItem> droppedFiles) async {
    final sftpProvider = context.read<SftpProvider>();
    final loc = AppLocalizations.of(context);

    for (final dropItem in droppedFiles) {
      final filePath = dropItem.path;
      final file = File(filePath);
      if (file.existsSync()) {
        final fileName = p.basename(filePath);
        final remotePath = '${sftpProvider.currentPath}/$fileName';

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => UploadProgressDialog(
              sftpService: sftpProvider.sftpService,
              fileName: fileName,
              localPath: filePath,
              remotePath: remotePath,
              onComplete: () {
                Navigator.pop(ctx);
                sftpProvider.listDirectory();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${loc.upload} $fileName ${loc.confirm}')),
                );
              },
            ),
          );
        }
      }
    }
  }

  Future<void> _uploadFiles(BuildContext context) async {
    final sftpProvider = context.read<SftpProvider>();
    final loc = AppLocalizations.of(context);

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      if (file.path == null) continue;
      final fileName = p.basename(file.path!);
      final remotePath = '${sftpProvider.currentPath}/$fileName';

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => UploadProgressDialog(
            sftpService: sftpProvider.sftpService,
            fileName: fileName,
            localPath: file.path!,
            remotePath: remotePath,
            onComplete: () {
              Navigator.pop(ctx);
              sftpProvider.listDirectory();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${loc.upload} $fileName ${loc.confirm}')),
              );
            },
          ),
        );
      }
    }
  }

  Future<void> _downloadFile(BuildContext context, String remotePath) async {
    final sftpProvider = context.read<SftpProvider>();
    final loc = AppLocalizations.of(context);

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: loc.download,
    );
    if (result == null) return;

    final fileName = p.basename(remotePath);
    final localPath = '$result/$fileName';

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => DownloadProgressDialog(
          sftpService: sftpProvider.sftpService,
          fileName: fileName,
          remotePath: remotePath,
          localPath: localPath,
          onComplete: () {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${loc.download} $fileName ${loc.confirm}')),
            );
          },
        ),
      );
    }
  }

  Future<void> _deleteFile(BuildContext context, String path) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text('Delete ${p.basename(path)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<SftpProvider>().sftpService.remove(path);
      await context.read<SftpProvider>().listDirectory();
    }
  }

  void _deleteSelected(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = context.read<SftpProvider>();
    final count = sftpProvider.selectedFiles.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text('Delete $count files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
        ],
      ),
    );
    if (confirmed == true) {
      await sftpProvider.deleteSelected();
    }
  }

  void _createFolder(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.newFolder),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.folderName),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await context.read<SftpProvider>().createDirectory(name);
    }
  }

  void _compressSelected(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = context.read<SftpProvider>();
    final controller = TextEditingController(text: 'archive.tar.gz');

    final archiveName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.compress),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.archiveName),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(loc.confirm),
          ),
        ],
      ),
    );

    if (archiveName != null && archiveName.isNotEmpty) {
      final outputPath = '${sftpProvider.currentPath}/$archiveName';
      final paths = sftpProvider.selectedFiles.toList();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => CompressionProgressDialog(
            compressionService: sftpProvider.compressionService,
            archiveName: archiveName,
            filePaths: paths,
            outputPath: outputPath,
            onComplete: () {
              Navigator.pop(ctx);
              sftpProvider.clearSelection();
              sftpProvider.listDirectory();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${loc.compress} $archiveName ${loc.confirm}')),
              );
            },
          ),
        );
      }
    }
  }
}
