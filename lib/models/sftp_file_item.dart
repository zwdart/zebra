enum SftpEntryType {
  unknown,
  regularFile,
  directory,
  symbolicLink,
  blockDevice,
  characterDevice,
  pipe,
  socket,
  whiteout,
}

class SftpFileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;
  final DateTime? accessAt;
  final int permissions;
  final int? uid;
  final int? gid;
  final SftpEntryType entryType;

  SftpFileItem({
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.size = 0,
    DateTime? modifiedAt,
    this.accessAt,
    this.permissions = 0,
    this.uid,
    this.gid,
    this.entryType = SftpEntryType.unknown,
  }) : modifiedAt = modifiedAt ?? DateTime.now();

  String get extension => isDirectory ? '' : name.split('.').last.toLowerCase();

  bool get isArchive {
    const archiveExts = ['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar'];
    return archiveExts.contains(extension);
  }

  bool get isSymbolicLink => entryType == SftpEntryType.symbolicLink;

  String get sizeText {
    if (isDirectory) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get permissionsText {
    String perms = '';
    switch (entryType) {
      case SftpEntryType.directory:
        perms += 'd';
        break;
      case SftpEntryType.symbolicLink:
        perms += 'l';
        break;
      case SftpEntryType.blockDevice:
        perms += 'b';
        break;
      case SftpEntryType.characterDevice:
        perms += 'c';
        break;
      case SftpEntryType.pipe:
        perms += 'p';
        break;
      case SftpEntryType.socket:
        perms += 's';
        break;
      default:
        perms += '-';
    }
    perms += (permissions & 0x100) != 0 ? 'r' : '-';
    perms += (permissions & 0x080) != 0 ? 'w' : '-';
    perms += (permissions & 0x040) != 0 ? 'x' : '-';
    perms += (permissions & 0x020) != 0 ? 'r' : '-';
    perms += (permissions & 0x010) != 0 ? 'w' : '-';
    perms += (permissions & 0x008) != 0 ? 'x' : '-';
    perms += (permissions & 0x004) != 0 ? 'r' : '-';
    perms += (permissions & 0x002) != 0 ? 'w' : '-';
    perms += (permissions & 0x001) != 0 ? 'x' : '-';
    return perms;
  }

  String get sizeAligned {
    if (isDirectory) return '      -';
    if (size < 1024) return size.toString().padLeft(7);
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} K'.padLeft(7);
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} M'.padLeft(7);
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} G'.padLeft(7);
  }

  String get dateText {
    final now = DateTime.now();
    final diff = now.difference(modifiedAt);
    if (diff.inDays > 180 || modifiedAt.year != now.year) {
      return '${_monthStr(modifiedAt.month)} ${modifiedAt.day.toString().padLeft(2)}  ${modifiedAt.year}';
    }
    return '${_monthStr(modifiedAt.month)} ${modifiedAt.day.toString().padLeft(2)} ${modifiedAt.hour.toString().padLeft(2)}:${modifiedAt.minute.toString().padLeft(2)}';
  }

  static String _monthStr(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }
}
