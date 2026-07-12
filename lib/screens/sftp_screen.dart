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
import '../widgets/batch_upload_dialog.dart';
import '../models/sftp_file_item.dart';
import '../services/sftp_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/file_conflict_dialog.dart';

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
  final List<String> _clipboardPaths = [];
  bool _clipboardIsCut = false;

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
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text(sftpProvider.currentPath),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (sftpProvider.canGoBack) {
              sftpProvider.goBack();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
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
            if (_clipboardPaths.isNotEmpty)
              IconButton(
                icon: Icon(_clipboardIsCut ? Icons.content_cut : Icons.copy),
                tooltip: loc.paste,
                onPressed: () => _pasteFiles(context),
              ),
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
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: sftpProvider.currentPath,
              showBackButton: true,
              onBack: () {
                if (sftpProvider.canGoBack) {
                  sftpProvider.goBack();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              showCloseButton: true,
              onClose: () => Navigator.of(context).maybePop(),
              actions: [
                if (sftpProvider.isSelectionMode) ...[
                  _buildTitleBarIconBtn(loc.selectAll, Icons.select_all, sftpProvider.selectAll),
                  _buildTitleBarIconBtn(loc.deselectAll, Icons.close, sftpProvider.clearSelection),
                  _buildTitleBarIconBtn(loc.delete, Icons.delete, () => _deleteSelected(context)),
                  _buildTitleBarIconBtn(loc.compress, Icons.archive, () => _compressSelected(context)),
                ] else ...[
                  if (_clipboardPaths.isNotEmpty)
                    _buildTitleBarIconBtn(loc.paste, _clipboardIsCut ? Icons.content_cut : Icons.copy, () => _pasteFiles(context)),
                  _buildTitleBarIconBtn(
                    _showRawValues ? loc.showConverted : loc.showRaw,
                    _showRawValues ? Icons.auto_awesome : Icons.code,
                    () => setState(() => _showRawValues = !_showRawValues),
                  ),
                  _buildTitleBarIconBtn(loc.sort, Icons.sort, () => _showSortMenu(context)),
                  _buildTitleBarIconBtn(loc.newFolder, Icons.create_new_folder, () => _createFolder(context)),
                  _buildTitleBarIconBtn(loc.upload, Icons.upload_file, () => _uploadFiles(context)),
                  _buildTitleBarIconBtn(loc.openTerminalHere, Icons.terminal, () => _openTerminalHere(context)),
                  _buildTitleBarIconBtn(loc.navigateToPath, Icons.folder_special, () => _navigateToPath(context)),
                ],
              ],
            ),
          Expanded(
            child: DropTarget(
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
                                              _editFile(context, file.path);
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
                                                value: 'rename',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.edit, size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.rename),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'copy',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.copy, size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.copy),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'cut',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.content_cut, size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.cut),
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
                      Text(loc.dragFilesOrFoldersHere,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  ],
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
        _editFile(context, file.path);
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
      case 'rename':
        _renameFile(context, file);
        break;
      case 'copy':
        _copyFiles(context, [file.path], false);
        break;
      case 'cut':
        _copyFiles(context, [file.path], true);
        break;
      case 'copyPath':
        Clipboard.setData(ClipboardData(text: file.path));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.pathCopied)),
          );
        }
        break;
    }
  }

  Widget _buildTitleBarIconBtn(String tooltip, IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  void _renameFile(BuildContext context, SftpFileItem file) {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController(text: file.name);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.rename),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.enterNewName),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(loc.confirm),
          ),
        ],
      ),
    ).then((newName) async {
      if (newName != null && newName.isNotEmpty && newName != file.name) {
        final sftpProvider = context.read<SftpProvider>();
        final oldPath = file.path;
        final newPath = '${sftpProvider.currentPath}/$newName';
        try {
          await sftpProvider.sftpService.rename(oldPath, newPath);
          await sftpProvider.listDirectory();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.fileRenamed)),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      }
    });
  }

  void _copyFiles(BuildContext context, List<String> paths, bool isCut) {
    final loc = AppLocalizations.of(context);
    setState(() {
      _clipboardPaths.clear();
      _clipboardPaths.addAll(paths);
      _clipboardIsCut = isCut;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCut ? loc.filesCut : loc.filesCopied)),
      );
    }
  }

  void _pasteFiles(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = context.read<SftpProvider>();
    final sshService = context.read<SshProvider>().sshService;

    if (_clipboardPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.noFilesToPaste)),
        );
      }
      return;
    }

    final destDir = sftpProvider.currentPath;
    final conflicts = <ConflictFileInfo>[];

    // 检查所有文件是否有冲突
    for (final srcPath in _clipboardPaths) {
      final fileName = srcPath.split('/').last;
      final destPath = '$destDir/$fileName';

      try {
        final stat = await sshService.execute('stat "$destPath" 2>/dev/null && echo "EXISTS" || echo "NOT_EXISTS"');
        if (stat.contains('EXISTS')) {
          // 获取文件大小
          int size = 0;
          try {
            final sizeResult = await sshService.execute('stat -c %s "$destPath" 2>/dev/null');
            size = int.tryParse(sizeResult.trim()) ?? 0;
          } catch (_) {}

          conflicts.add(ConflictFileInfo(
            fileName: fileName,
            sourcePath: srcPath,
            destPath: destPath,
            size: size,
          ));
        }
      } catch (e) {
        // 如果检查失败，继续
      }
    }

    // 如果有冲突，显示对话框
    ConflictAction action = ConflictAction.rename;
    if (conflicts.isNotEmpty) {
      final result = await FileConflictDialog.show(
        context,
        conflicts: conflicts,
        isCut: _clipboardIsCut,
      );
      if (result == null) return; // 用户取消
      action = result;
    }

    // 执行粘贴操作
    for (final srcPath in _clipboardPaths) {
      final fileName = srcPath.split('/').last;
      var destPath = '$destDir/$fileName';
      final hasConflict = conflicts.any((c) => c.sourcePath == srcPath);

      if (hasConflict) {
        switch (action) {
          case ConflictAction.skip:
            continue;
          case ConflictAction.overwrite:
            // 直接覆盖，不做任何处理
            break;
          case ConflictAction.rename:
            // 生成新文件名
            destPath = await _generateUniqueFileName(sshService, destDir, fileName);
            break;
        }
      }

      try {
        if (_clipboardIsCut) {
          await sshService.execute('mv "$srcPath" "$destPath"');
        } else {
          await sshService.execute('cp -r "$srcPath" "$destPath"');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }

    final wasCut = _clipboardIsCut;
    setState(() {
      _clipboardPaths.clear();
      _clipboardIsCut = false;
    });

    await sftpProvider.listDirectory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wasCut ? loc.fileMoved : loc.filesCopied)),
      );
    }
  }

  Future<String> _generateUniqueFileName(
    dynamic sshService,
    String destDir,
    String originalName,
  ) async {
    final extension = originalName.contains('.')
        ? '.${originalName.split('.').last}'
        : '';
    final baseName = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;

    int counter = 1;
    while (true) {
      final newFileName = '$baseName ($counter)$extension';
      final newPath = '$destDir/$newFileName';
      try {
        final result = await sshService.execute('stat "$newPath" 2>/dev/null && echo "EXISTS" || echo "NOT_EXISTS"');
        if (!result.contains('EXISTS')) {
          return newPath;
        }
      } catch (_) {
        return newPath;
      }
      counter++;
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
      // Try to read with 5MB limit
      final content = await sftpProvider.sftpService.readFileContent(remotePath);
      if (content != null) {
        // File is within size limit, open editor
        _openEditor(context, remotePath, content, loc);
        return;
      }

      // File is too large, try to read for preview only
      final size = await sftpProvider.sftpService.getFileSize(remotePath);
      if (size > 5 * 1024 * 1024) {
        // Show read-only preview for large files
        if (mounted) {
          _showLargeFilePreview(context, remotePath, size, loc);
        }
        return;
      }

      // Other error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot read file')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _openEditor(BuildContext context, String remotePath, String content, AppLocalizations loc) {
    final controller = TextEditingController(text: content);
    showDialog<String>(
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
    ).then((result) async {
      if (result != null && result != content) {
        final sftpProvider = context.read<SftpProvider>();
        await sftpProvider.sftpService.writeFileContent(remotePath, result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.basename(remotePath)} saved')),
          );
        }
      }
    });
  }

  void _showLargeFilePreview(BuildContext context, String remotePath, int fileSize, AppLocalizations loc) {
    final sftpProvider = context.read<SftpProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${loc.viewFile} - ${p.basename(remotePath)}'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Theme.of(ctx).colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'File size: ${_formatFileSize(fileSize)} - Read-only preview',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<String?>(
                  future: _readLastLines(sftpProvider.sftpService, remotePath, 1000),
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Center(child: Text('Failed to load file'));
                    }
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(
                        snapshot.data!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
        ],
      ),
    );
  }

  Future<String?> _readLastLines(SftpService sftpService, String remotePath, int maxLines) async {
    try {
      // Read the file content with 5MB limit
      final content = await sftpService.readFileContent(remotePath);
      if (content == null) return null;

      // Get last N lines
      final lines = content.split('\n');
      final lastLines = lines.length > maxLines
          ? lines.sublist(lines.length - maxLines)
          : lines;
      return lastLines.join('\n');
    } catch (e) {
      return null;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _handleDroppedFiles(List<DropItem> droppedFiles) async {
    final sftpProvider = context.read<SftpProvider>();

    final items = <BatchUploadItem>[];

    for (final dropItem in droppedFiles) {
      final filePath = dropItem.path;
      final entity = FileSystemEntity.typeSync(filePath);

      if (entity == FileSystemEntityType.directory) {
        // Recursively collect files from directory
        final dirName = p.basename(filePath);
        final remoteDirPath = '${sftpProvider.currentPath}/$dirName';
        items.add(BatchUploadItem(
          localPath: filePath,
          remotePath: remoteDirPath,
          isDirectory: true,
        ));
        _collectDirectoryFiles(filePath, remoteDirPath, items);
      } else if (entity == FileSystemEntityType.file) {
        final fileName = p.basename(filePath);
        final remotePath = '${sftpProvider.currentPath}/$fileName';
        final localFile = File(filePath);
        final fileSize = localFile.existsSync() ? localFile.lengthSync() : 0;
        items.add(BatchUploadItem(
          localPath: filePath,
          remotePath: remotePath,
          size: fileSize,
        ));
      }
    }

    if (items.isEmpty) return;

    final filteredItems = await _checkConflictsAndFilter(items);
    if (filteredItems == null || filteredItems.isEmpty) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => BatchUploadProgressDialog(
          sftpService: sftpProvider.sftpService,
          items: filteredItems,
          onComplete: () {
            sftpProvider.listDirectory();
          },
        ),
      );
    }
  }

  void _collectDirectoryFiles(String localDir, String remoteDir, List<BatchUploadItem> items) {
    final dir = Directory(localDir);
    if (!dir.existsSync()) return;

    try {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final remotePath = '$remoteDir/$fileName';
          final fileSize = entity.existsSync() ? entity.lengthSync() : 0;
          items.add(BatchUploadItem(
            localPath: entity.path,
            remotePath: remotePath,
            size: fileSize,
          ));
        } else if (entity is Directory) {
          final dirName = p.basename(entity.path);
          final remotePath = '$remoteDir/$dirName';
          items.add(BatchUploadItem(
            localPath: entity.path,
            remotePath: remotePath,
            isDirectory: true,
          ));
          _collectDirectoryFiles(entity.path, remotePath, items);
        }
      }
    } catch (e) {
      // Skip inaccessible directories
    }
  }

  Future<List<BatchUploadItem>?> _checkConflictsAndFilter(List<BatchUploadItem> items) async {
    final sftpProvider = context.read<SftpProvider>();
    final sftpService = sftpProvider.sftpService;

    final fileItems = items.where((i) => !i.isDirectory).toList();
    if (fileItems.isEmpty) return items;

    final conflicts = <ConflictFileInfo>[];
    for (final item in fileItems) {
      try {
        final exists = await sftpService.fileExists(item.remotePath);
        if (exists) {
          final localFile = File(item.localPath);
          final size = localFile.existsSync() ? localFile.lengthSync() : 0;
          conflicts.add(ConflictFileInfo(
            fileName: p.basename(item.localPath),
            sourcePath: item.localPath,
            destPath: item.remotePath,
            size: size,
          ));
        }
      } catch (_) {
        // If check fails, assume no conflict
      }
    }

    if (conflicts.isEmpty) return items;

    final action = await FileConflictDialog.show(
      context,
      conflicts: conflicts,
      isCut: false,
      isUpload: true,
    );
    if (action == null) return null;

    final filteredItems = <BatchUploadItem>[];
    for (final item in items) {
      if (item.isDirectory) {
        filteredItems.add(item);
        continue;
      }

      final hasConflict = conflicts.any((c) => c.sourcePath == item.localPath);
      if (!hasConflict) {
        filteredItems.add(item);
        continue;
      }

      switch (action) {
        case ConflictAction.skip:
          break;
        case ConflictAction.overwrite:
          filteredItems.add(item);
          break;
        case ConflictAction.rename:
          final fileName = p.basename(item.localPath);
          final dir = p.dirname(item.remotePath);
          final newName = await _generateUniqueFileNameForUpload(sftpService, dir, fileName);
          filteredItems.add(BatchUploadItem(
            localPath: item.localPath,
            remotePath: newName,
            size: item.size,
          ));
          break;
      }
    }

    return filteredItems;
  }

  Future<String> _generateUniqueFileNameForUpload(
    SftpService sftpService,
    String destDir,
    String originalName,
  ) async {
    final extension = originalName.contains('.')
        ? '.${originalName.split('.').last}'
        : '';
    final baseName = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;

    int counter = 1;
    while (true) {
      final newFileName = '$baseName ($counter)$extension';
      final newPath = '$destDir/$newFileName';
      try {
        final exists = await sftpService.fileExists(newPath);
        if (!exists) {
          return newPath;
        }
      } catch (_) {
        return newPath;
      }
      counter++;
    }
  }

  Future<void> _uploadFiles(BuildContext context) async {
    final sftpProvider = context.read<SftpProvider>();
    final loc = AppLocalizations.of(context);

    // Show choice dialog for files vs folders
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.upload),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'files'),
            child: Row(
              children: [
                const Icon(Icons.upload_file),
                const SizedBox(width: 12),
                Text(loc.uploadFiles),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'folders'),
            child: Row(
              children: [
                const Icon(Icons.folder),
                const SizedBox(width: 12),
                Text(loc.uploadFolders),
              ],
            ),
          ),
        ],
      ),
    );

    if (choice == null) return;

    final items = <BatchUploadItem>[];

    if (choice == 'files') {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.path == null) continue;

        final entity = FileSystemEntity.typeSync(file.path!);
        if (entity == FileSystemEntityType.directory) {
          // 用户选中了目录，递归收集目录内容
          final dirName = p.basename(file.path!);
          final remoteDirPath = '${sftpProvider.currentPath}/$dirName';
          items.add(BatchUploadItem(
            localPath: file.path!,
            remotePath: remoteDirPath,
            isDirectory: true,
          ));
          _collectDirectoryFiles(file.path!, remoteDirPath, items);
        } else if (entity == FileSystemEntityType.file) {
          final fileName = p.basename(file.path!);
          final remotePath = '${sftpProvider.currentPath}/$fileName';
          final localFile = File(file.path!);
          final fileSize = localFile.existsSync() ? localFile.lengthSync() : 0;
          items.add(BatchUploadItem(
            localPath: file.path!,
            remotePath: remotePath,
            size: fileSize,
          ));
        }
      }
    } else if (choice == 'folders') {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: loc.uploadFolders,
      );
      if (dirPath == null) return;

      final dirName = p.basename(dirPath);
      final remoteDirPath = '${sftpProvider.currentPath}/$dirName';
      items.add(BatchUploadItem(
        localPath: dirPath,
        remotePath: remoteDirPath,
        isDirectory: true,
      ));
      _collectDirectoryFiles(dirPath, remoteDirPath, items);
    }

    if (items.isEmpty) return;

    final filteredItems = await _checkConflictsAndFilter(items);
    if (filteredItems == null || filteredItems.isEmpty) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => BatchUploadProgressDialog(
          sftpService: sftpProvider.sftpService,
          items: filteredItems,
          onComplete: () {
            sftpProvider.listDirectory();
          },
        ),
      );
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
    final localPath = p.join(result, fileName);

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
    final name = p.basename(path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text('Delete "$name" and all its contents?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<SftpProvider>().remove(path);
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
