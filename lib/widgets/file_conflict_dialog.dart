import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

enum ConflictAction { overwrite, rename, skip }

class ConflictFileInfo {
  final String fileName;
  final String sourcePath;
  final String destPath;
  final int size;
  final bool isDirectory;

  ConflictFileInfo({
    required this.fileName,
    required this.sourcePath,
    required this.destPath,
    required this.size,
    this.isDirectory = false,
  });
}

class FileConflictDialog extends StatelessWidget {
  final List<ConflictFileInfo> conflicts;
  final bool isCut;
  final bool isUpload;

  const FileConflictDialog({
    super.key,
    required this.conflicts,
    required this.isCut,
    this.isUpload = false,
  });

  static Future<ConflictAction?> show(
    BuildContext context, {
    required List<ConflictFileInfo> conflicts,
    required bool isCut,
    bool isUpload = false,
  }) async {
    return showDialog<ConflictAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FileConflictDialog(
        conflicts: conflicts,
        isCut: isCut,
        isUpload: isUpload,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isUpload
          ? loc.fileConflictTitleUpload
          : (isCut ? loc.fileConflictTitleMove : loc.fileConflictTitleCopy)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUpload
                  ? loc.fileConflictMessageUpload
                  : (isCut ? loc.fileConflictMessageMove : loc.fileConflictMessageCopy),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: conflicts.length,
                itemBuilder: (context, index) {
                  final conflict = conflicts[index];
                  return ListTile(
                    leading: Icon(
                      conflict.isDirectory ? Icons.folder : Icons.insert_drive_file,
                      color: conflict.isDirectory ? Colors.amber : Colors.blue,
                    ),
                    title: Text(
                      conflict.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      conflict.isDirectory
                          ? loc.directory
                          : _formatSize(conflict.size),
                    ),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictAction.skip),
          child: Text(loc.skipAll),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictAction.rename),
          child: Text(loc.renameAll),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ConflictAction.overwrite),
          child: Text(loc.overwriteAll),
        ),
      ],
    );
  }
}