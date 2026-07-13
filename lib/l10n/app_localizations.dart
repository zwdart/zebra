import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  Map<String, String> get _translations {
    switch (locale.languageCode) {
      case 'zh':
        return _zh;
      default:
        return _en;
    }
  }

  String translate(String key) => _translations[key] ?? key;

  String get appTitle => translate('appTitle');
  String get connections => translate('connections');
  String get addConnection => translate('addConnection');
  String get editConnection => translate('editConnection');
  String get deleteConnection => translate('deleteConnection');
  String get connectionName => translate('connectionName');
  String get host => translate('host');
  String get port => translate('port');
  String get username => translate('username');
  String get password => translate('password');
  String get privateKey => translate('privateKey');
  String get passphrase => translate('passphrase');
  String get remark => translate('remark');
  String get authType => translate('authType');
  String get passwordAuth => translate('passwordAuth');
  String get keyAuth => translate('keyAuth');
  String get connect => translate('connect');
  String get disconnect => translate('disconnect');
  String get terminal => translate('terminal');
  String get sftp => translate('sftp');
  String get settings => translate('settings');
  String get theme => translate('theme');
  String get language => translate('language');
  String get darkMode => translate('darkMode');
  String get lightMode => translate('lightMode');
  String get systemMode => translate('systemMode');
  String get upload => translate('upload');
  String get download => translate('download');
  String get newFolder => translate('newFolder');
  String get delete => translate('delete');
  String get rename => translate('rename');
  String get copy => translate('copy');
  String get cut => translate('cut');
  String get paste => translate('paste');
  String get filesCopied => translate('filesCopied');
  String get filesCut => translate('filesCut');
  String get fileRenamed => translate('fileRenamed');
  String get fileMoved => translate('fileMoved');
  String get enterNewName => translate('enterNewName');
  String get noFilesToPaste => translate('noFilesToPaste');
  String get selectAll => translate('selectAll');
  String get deselectAll => translate('deselectAll');
  String get compress => translate('compress');
  String get cancel => translate('cancel');
  String get confirm => translate('confirm');
  String get save => translate('save');
  String get search => translate('search');
  String get noConnections => translate('noConnections');
  String get connecting => translate('connecting');
  String get connectionError => translate('connectionError');
  String get uploadProgress => translate('uploadProgress');
  String get downloadProgress => translate('downloadProgress');
  String get compressionProgress => translate('compressionProgress');
  String get dragFilesHere => translate('dragFilesHere');
  String get name => translate('name');
  String get size => translate('size');
  String get modified => translate('modified');
  String get permissions => translate('permissions');
  String get confirmDelete => translate('confirmDelete');
  String get confirmDeleteMsg => translate('confirmDeleteMsg');
  String get folderName => translate('folderName');
  String get archiveName => translate('archiveName');
  String get selectThemeColor => translate('selectThemeColor');
  String get viewFile => translate('viewFile');
  String get editFile => translate('editFile');
  String get openTerminalHere => translate('openTerminalHere');
  String get navigateToPath => translate('navigateToPath');
  String get enterPath => translate('enterPath');
  String get fuzzySearch => translate('fuzzySearch');
  String get searchFiles => translate('searchFiles');
  String get copyPath => translate('copyPath');
  String get pathCopied => translate('pathCopied');
  String get showRaw => translate('showRaw');
  String get showConverted => translate('showConverted');
  String get sort => translate('sort');
  String get sortBy => translate('sortBy');
  String get sortByName => translate('sortByName');
  String get sortBySize => translate('sortBySize');
  String get sortByDate => translate('sortByDate');
  String get ascending => translate('ascending');
  String get descending => translate('descending');
  String get serverMonitor => translate('serverMonitor');
  String get systemInfo => translate('systemInfo');
  String get cpuUsage => translate('cpuUsage');
  String get memory => translate('memory');
  String get disk => translate('disk');
  String get loadAverage => translate('loadAverage');
  String get network => translate('network');
  String get processes => translate('processes');
  String get hostname => translate('hostname');
  String get operatingSystem => translate('operatingSystem');
  String get kernel => translate('kernel');
  String get cpuModelLabel => translate('cpuModelLabel');
  String get cpuCores => translate('cpuCores');
  String get frequency => translate('frequency');
  String get uptimeLabel => translate('uptimeLabel');
  String get available => translate('available');
  String get received => translate('received');
  String get sent => translate('sent');
  String get runningProcesses => translate('runningProcesses');
  String get autoRefresh => translate('autoRefresh');
  String get pauseRefresh => translate('pauseRefresh');
  String get refreshInterval => translate('refreshInterval');
  String get refresh => translate('refresh');
  String get retry => translate('retry');
  String get lastUpdated => translate('lastUpdated');
  String get processList => translate('processList');
  String get searchProcesses => translate('searchProcesses');
  String get noProcessesFound => translate('noProcessesFound');
  String get killProcess => translate('killProcess');
  String get killSystemProcess => translate('killSystemProcess');
  String get confirmKillSystemProcess => translate('confirmKillSystemProcess');
  String get kill => translate('kill');
  String get killFailed => translate('killFailed');
  String get sortByCpu => translate('sortByCpu');
  String get sortByMem => translate('sortByMem');
  String get sortByMemSize => translate('sortByMemSize');
  String get sortByPid => translate('sortByPid');
  String get sortByUser => translate('sortByUser');
  String get user => translate('user');
  String get memSize => translate('memSize');
  String confirmKillSystemProcessMsg(int pid, String user) {
    return translate('confirmKillSystemProcessMsg').replaceAll('{pid}', '$pid').replaceAll('{user}', user);
  }
  String processSentSignal(int pid) {
    return translate('processSentSignal').replaceAll('{pid}', '$pid');
  }
  String get diskCleanup => translate('diskCleanup');
  String get totalCleanable => translate('totalCleanable');
  String get quickClean => translate('quickClean');
  String get tempFileBrowser => translate('tempFileBrowser');
  String get clean => translate('clean');
  String get cleanAll => translate('cleanAll');
  String cleanAllMsgParam(String size) {
    return translate('cleanAllMsg').replaceAll('{size}', size);
  }
  String cleanCompleted(String label) {
    return translate('cleanCompleted').replaceAll('{label}', label);
  }
  String get cleanFailed => translate('cleanFailed');
  String get confirmClean => translate('confirmClean');
  String get scanTempFiles => translate('scanTempFiles');
  String get scanTempFilesDesc => translate('scanTempFilesDesc');
  String get scan => translate('scan');
  String get rescan => translate('rescan');
  String get confirmDeleteSelected => translate('confirmDeleteSelected');
  String confirmDeleteSelectedMsg(int count) {
    return translate('confirmDeleteSelectedMsg').replaceAll('{count}', '$count');
  }
  String deletedFiles(int count) {
    return translate('deletedFiles').replaceAll('{count}', '$count');
  }
  String get deleteFailed => translate('deleteFailed');
  String get recentLogins => translate('recentLogins');
  String get noLoginHistory => translate('noLoginHistory');
  String get failedLogins => translate('failedLogins');
  String get noFailedLogins => translate('noFailedLogins');
  String get uninstallFromSystem => translate('uninstallFromSystem');
  String get uninstallSuccess => translate('uninstallSuccess');
  String get uninstallFailed => translate('uninstallFailed');
  String get confirmUninstall => translate('confirmUninstall');
  String get confirmUninstallMsg => translate('confirmUninstallMsg');
  String get systemIntegration => translate('systemIntegration');
  String get newTab => translate('newTab');
  String get noSessions => translate('noSessions');
  String get closeTab => translate('closeTab');
  String get closeOtherTabs => translate('closeOtherTabs');
  String get closeAllTabs => translate('closeAllTabs');
  String get showWindow => translate('showWindow');
  String get hideWindow => translate('hideWindow');
  String get quit => translate('quit');
  String get uploading => translate('uploading');
  String get batchUpload => translate('batchUpload');
  String get uploadFiles => translate('uploadFiles');
  String get uploadFolders => translate('uploadFolders');
  String get filesReady => translate('filesReady');
  String get uploadingFile => translate('uploadingFile');
  String get uploadCompleted => translate('uploadCompleted');
  String get uploadFailed => translate('uploadFailed');
  String get skipFailed => translate('skipFailed');
  String get retryFailed => translate('retryFailed');
  String get creatingFolders => translate('creatingFolders');
  String get dragFilesOrFoldersHere => translate('dragFilesOrFoldersHere');
  String get transferSpeed => translate('transferSpeed');
  String get estimatedTime => translate('estimatedTime');
  String get fileProgress => translate('fileProgress');
  String get totalProgress => translate('totalProgress');
  String get waiting => translate('waiting');
  String get shareDatabase => translate('shareDatabase');
  String get about => translate('about');
  String get featuresAndUsage => translate('featuresAndUsage');
  String get aboutUs => translate('aboutUs');
  String get version => translate('version');
  String get developer => translate('developer');
  String get contactUs => translate('contactUs');
  String get openSourceLicenses => translate('openSourceLicenses');
  String get website => translate('website');
  String get shop => translate('shop');
  String get uniqueId => translate('uniqueId');
  String get uniqueIdCopied => translate('uniqueIdCopied');
  String get buildTime => translate('buildTime');
  String get fileConflictTitleCopy => translate('fileConflictTitleCopy');
  String get fileConflictTitleMove => translate('fileConflictTitleMove');
  String get fileConflictTitleUpload => translate('fileConflictTitleUpload');
  String get fileConflictMessageCopy => translate('fileConflictMessageCopy');
  String get fileConflictMessageMove => translate('fileConflictMessageMove');
  String get fileConflictMessageUpload => translate('fileConflictMessageUpload');
  String get overwriteAll => translate('overwriteAll');
  String get renameAll => translate('renameAll');
  String get skipAll => translate('skipAll');
  String get directory => translate('directory');
  String get checkForUpdates => translate('checkForUpdates');
  String get checkingForUpdate => translate('checkingForUpdate');
  String get newVersionAvailable => translate('newVersionAvailable');
  String get noUpdatesAvailable => translate('noUpdatesAvailable');
  String get currentVersionIsLatest => translate('currentVersionIsLatest');
  String get updateCheckFailed => translate('updateCheckFailed');
  String get unknownError => translate('unknownError');
  String get downloadNow => translate('downloadNow');
  String get updateNow => translate('updateNow');
  String get openLink => translate('openLink');
  String get downloadingUpdate => translate('downloadingUpdate');
  String get downloadComplete => translate('downloadComplete');
  String get downloadCompleteMsg => translate('downloadCompleteMsg');
  String get installNow => translate('installNow');
  String get skip => translate('skip');
  String get forceUpdateRequired => translate('forceUpdateRequired');
  String get forceUpdateMessage => translate('forceUpdateMessage');
  String get changelog => translate('changelog');
  String get releaseDate => translate('releaseDate');
  String get fileSize => translate('fileSize');

  static const Map<String, String> _en = {
    'appTitle': 'Zebra SSH',
    'connections': 'Connections',
    'addConnection': 'Add Connection',
    'editConnection': 'Edit Connection',
    'deleteConnection': 'Delete Connection',
    'connectionName': 'Connection Name',
    'host': 'Host',
    'port': 'Port',
    'username': 'Username',
    'password': 'Password',
    'privateKey': 'Private Key',
    'passphrase': 'Passphrase',
    'remark': 'Remark',
    'authType': 'Auth Type',
    'passwordAuth': 'Password',
    'keyAuth': 'Private Key',
    'connect': 'Connect',
    'disconnect': 'Disconnect',
    'terminal': 'Terminal',
    'sftp': 'SFTP',
    'settings': 'Settings',
    'theme': 'Theme',
    'language': 'Language',
    'darkMode': 'Dark Mode',
    'lightMode': 'Light Mode',
    'systemMode': 'System Mode',
    'upload': 'Upload',
    'download': 'Download',
    'newFolder': 'New Folder',
    'delete': 'Delete',
    'rename': 'Rename',
    'copy': 'Copy',
    'cut': 'Cut',
    'paste': 'Paste',
    'filesCopied': 'Files copied',
    'filesCut': 'Files cut',
    'fileRenamed': 'File renamed',
    'fileMoved': 'File moved',
    'enterNewName': 'Enter new name',
    'noFilesToPaste': 'No files to paste',
    'selectAll': 'Select All',
    'deselectAll': 'Deselect All',
    'compress': 'Compress',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'save': 'Save',
    'search': 'Search',
    'noConnections': 'No connections yet',
    'connecting': 'Connecting...',
    'connectionError': 'Connection Error',
    'uploadProgress': 'Upload Progress',
    'downloadProgress': 'Download Progress',
    'compressionProgress': 'Compression Progress',
    'dragFilesHere': 'Drag files here to upload',
    'name': 'Name',
    'size': 'Size',
    'modified': 'Modified',
    'permissions': 'Permissions',
    'confirmDelete': 'Confirm Delete',
    'confirmDeleteMsg': 'Are you sure you want to delete this connection?',
    'folderName': 'Folder Name',
    'archiveName': 'Archive Name',
    'selectThemeColor': 'Select Theme Color',
    'viewFile': 'View File',
    'editFile': 'Edit File',
    'openTerminalHere': 'Open Terminal Here',
    'navigateToPath': 'Go to Path',
    'enterPath': 'Enter path',
    'fuzzySearch': 'Search',
    'searchFiles': 'Search files and folders...',
    'copyPath': 'Copy Path',
    'pathCopied': 'Path copied to clipboard',
    'showRaw': 'Show Raw Values',
    'showConverted': 'Show Converted Values',
    'sort': 'Sort',
    'sortBy': 'Sort By',
    'sortByName': 'Name',
    'sortBySize': 'Size',
    'sortByDate': 'Modified Date',
    'ascending': 'Ascending',
    'descending': 'Descending',
    'serverMonitor': 'Server Monitor',
    'systemInfo': 'System Info',
    'cpuUsage': 'CPU Usage',
    'memory': 'Memory',
    'disk': 'Disk',
    'loadAverage': 'Load Average',
    'network': 'Network',
    'processes': 'Processes',
    'hostname': 'Hostname',
    'operatingSystem': 'Operating System',
    'kernel': 'Kernel',
    'cpuModelLabel': 'CPU Model',
    'cpuCores': 'Cores',
    'frequency': 'Frequency',
    'uptimeLabel': 'Uptime',
    'available': 'Available',
    'received': 'Received',
    'sent': 'Sent',
    'runningProcesses': 'running processes',
    'autoRefresh': 'Auto Refresh',
    'pauseRefresh': 'Pause Refresh',
    'refreshInterval': 'Refresh Interval',
    'refresh': 'Refresh',
    'retry': 'Retry',
    'lastUpdated': 'Last Updated',
    'processList': 'Process List',
    'searchProcesses': 'Search processes...',
    'noProcessesFound': 'No processes found',
    'killProcess': 'Kill Process',
    'killSystemProcess': 'Kill System Process (Confirm)',
    'confirmKillSystemProcess': 'Kill System Process?',
    'confirmKillSystemProcessMsg': 'Process {pid} (user: {user}) is a system process. Are you sure you want to kill it?',
    'kill': 'Kill',
    'killFailed': 'Failed to kill process',
    'sortByCpu': 'CPU Usage',
    'sortByMem': 'Memory Usage',
    'sortByMemSize': 'Memory Size (RSS)',
    'sortByPid': 'PID',
    'sortByUser': 'User',
    'user': 'User',
    'memSize': 'RSS',
    'processSentSignal': 'Sent SIGTERM to process {pid}',
    'diskCleanup': 'Disk Cleanup',
    'totalCleanable': 'Total Cleanable',
    'quickClean': 'Quick Clean',
    'tempFileBrowser': 'Temporary File Browser',
    'clean': 'Clean',
    'cleanAll': 'Clean All',
    'cleanAllMsg': 'Clean all junk files? Total: {size}',
    'cleanCompleted': 'Cleaned: {label}',
    'cleanFailed': 'Clean failed',
    'confirmClean': 'Confirm Clean?',
    'scanTempFiles': 'Scan Temp Files',
    'scanTempFilesDesc': 'Scan /tmp, logs and cache for large files',
    'scan': 'Scan',
    'rescan': 'Rescan',
    'confirmDeleteSelected': 'Delete Selected?',
    'confirmDeleteSelectedMsg': 'Delete {count} selected files?',
    'deletedFiles': 'Deleted {count} files',
    'deleteFailed': 'Delete failed',
    'recentLogins': 'Recent Logins',
    'noLoginHistory': 'No login history',
    'failedLogins': 'Failed Logins',
    'noFailedLogins': 'No failed logins in the last 7 days',
    'uninstallFromSystem': 'Uninstall',
    'uninstallSuccess': 'Uninstalled successfully',
    'uninstallFailed': 'Uninstall failed',
    'confirmUninstall': 'Confirm Uninstall',
    'confirmUninstallMsg': 'This will remove the application from your system. Continue?',
    'systemIntegration': 'System Integration',
    'newTab': 'New Tab',
    'noSessions': 'No sessions',
    'closeTab': 'Close Tab',
    'closeOtherTabs': 'Close Other Tabs',
    'closeAllTabs': 'Close All Tabs',
    'showWindow': 'Show Window',
    'hideWindow': 'Hide Window',
    'quit': 'Quit',
    'uploading': 'Uploading',
    'batchUpload': 'Batch Upload',
    'uploadFiles': 'Upload Files',
    'uploadFolders': 'Upload Folders',
    'filesReady': '{count} files ready',
    'uploadingFile': 'Uploading: {file}',
    'uploadCompleted': 'Upload completed',
    'uploadFailed': 'Upload failed',
    'skipFailed': 'Skip failed',
    'retryFailed': 'Retry failed',
    'creatingFolders': 'Creating folders...',
    'dragFilesOrFoldersHere': 'Drag files or folders here to upload',
    'transferSpeed': 'Speed',
    'estimatedTime': 'ETA',
    'fileProgress': 'File',
    'totalProgress': 'Total',
    'waiting': 'Waiting...',
    'shareDatabase': 'Share Database',
    'about': 'About',
    'featuresAndUsage': 'Features & Usage',
    'aboutUs': 'About Us',
    'version': 'Version',
    'developer': 'Developer',
    'contactUs': 'Contact Us',
    'openSourceLicenses': 'Open Source Licenses',
    'website': 'Website',
    'shop': 'My Shop',
    'uniqueId': 'Unique ID',
    'uniqueIdCopied': 'ID copied to clipboard',
    'buildTime': 'Build Time',
    'fileConflictTitleCopy': 'File Conflict',
    'fileConflictTitleMove': 'File Conflict',
    'fileConflictTitleUpload': 'File Conflict',
    'fileConflictMessageCopy': 'The following files already exist in the destination. How would you like to proceed?',
    'fileConflictMessageMove': 'The following files already exist in the destination. How would you like to proceed?',
    'fileConflictMessageUpload': 'The following files already exist on the server. How would you like to proceed?',
    'overwriteAll': 'Overwrite All',
    'renameAll': 'Rename All',
    'skipAll': 'Skip All',
    'directory': 'Directory',
    'checkForUpdates': 'Check for Updates',
    'checkingForUpdate': 'Checking for updates...',
    'newVersionAvailable': 'New Version Available',
    'noUpdatesAvailable': 'No Updates Available',
    'currentVersionIsLatest': 'Your current version is up to date.',
    'updateCheckFailed': 'Update Check Failed',
    'unknownError': 'An unknown error occurred.',
    'downloadNow': 'Download',
    'updateNow': 'Update',
    'openLink': 'Open Link',
    'downloadingUpdate': 'Downloading Update...',
    'downloadComplete': 'Download Complete',
    'downloadCompleteMsg': 'The update has been downloaded. Click "Install" to start the installation.',
    'installNow': 'Install',
    'skip': 'Skip',
    'forceUpdateRequired': 'Force Update Required',
    'forceUpdateMessage': 'This update is required. You must update to continue using the app.',
    'changelog': 'Changelog',
    'releaseDate': 'Release Date',
    'fileSize': 'File Size',
  };

  static const Map<String, String> _zh = {
    'appTitle': 'Zebra SSH',
    'connections': '连接列表',
    'addConnection': '添加连接',
    'editConnection': '编辑连接',
    'deleteConnection': '删除连接',
    'connectionName': '连接名称',
    'host': '主机',
    'port': '端口',
    'username': '用户名',
    'password': '密码',
    'privateKey': '私钥',
    'passphrase': '密钥密码',
    'remark': '备注',
    'authType': '认证方式',
    'passwordAuth': '密码',
    'keyAuth': '密钥',
    'connect': '连接',
    'disconnect': '断开',
    'terminal': '终端',
    'sftp': '文件管理',
    'settings': '设置',
    'theme': '主题',
    'language': '语言',
    'darkMode': '深色模式',
    'lightMode': '浅色模式',
    'systemMode': '跟随系统',
    'upload': '上传',
    'download': '下载',
    'newFolder': '新建文件夹',
    'delete': '删除',
    'rename': '重命名',
    'copy': '复制',
    'cut': '剪切',
    'paste': '粘贴',
    'filesCopied': '文件已复制',
    'filesCut': '文件已剪切',
    'fileRenamed': '文件已重命名',
    'fileMoved': '文件已移动',
    'enterNewName': '输入新名称',
    'noFilesToPaste': '没有可粘贴的文件',
    'selectAll': '全选',
    'deselectAll': '取消全选',
    'compress': '压缩',
    'cancel': '取消',
    'confirm': '确认',
    'save': '保存',
    'search': '搜索',
    'noConnections': '暂无连接',
    'connecting': '连接中...',
    'connectionError': '连接错误',
    'uploadProgress': '上传进度',
    'downloadProgress': '下载进度',
    'compressionProgress': '压缩进度',
    'dragFilesHere': '拖拽文件到此处上传',
    'name': '名称',
    'size': '大小',
    'modified': '修改时间',
    'permissions': '权限',
    'confirmDelete': '确认删除',
    'confirmDeleteMsg': '确定要删除此连接吗？',
    'folderName': '文件夹名称',
    'archiveName': '压缩包名称',
    'selectThemeColor': '选择主题颜色',
    'viewFile': '查看文件',
    'editFile': '编辑文件',
    'openTerminalHere': '在此打开终端',
    'navigateToPath': '前往路径',
    'enterPath': '输入路径',
    'fuzzySearch': '搜索',
    'searchFiles': '搜索文件和文件夹...',
    'copyPath': '复制路径',
    'pathCopied': '路径已复制到剪贴板',
    'showRaw': '显示原始值',
    'showConverted': '显示转换值',
    'sort': '排序',
    'sortBy': '排序方式',
    'sortByName': '名称',
    'sortBySize': '大小',
    'sortByDate': '修改时间',
    'ascending': '升序',
    'descending': '降序',
    'serverMonitor': '服务器监控',
    'systemInfo': '系统信息',
    'cpuUsage': 'CPU 使用率',
    'memory': '内存',
    'disk': '磁盘',
    'loadAverage': '负载均衡',
    'network': '网络',
    'processes': '进程',
    'hostname': '主机名',
    'operatingSystem': '操作系统',
    'kernel': '内核',
    'cpuModelLabel': 'CPU 型号',
    'cpuCores': '核心数',
    'frequency': '频率',
    'uptimeLabel': '运行时间',
    'available': '可用',
    'received': '接收',
    'sent': '发送',
    'runningProcesses': '个运行进程',
    'autoRefresh': '自动刷新',
    'pauseRefresh': '暂停刷新',
    'refreshInterval': '刷新间隔',
    'refresh': '刷新',
    'retry': '重试',
    'lastUpdated': '最后更新',
    'processList': '进程列表',
    'searchProcesses': '搜索进程...',
    'noProcessesFound': '未找到进程',
    'killProcess': '终止进程',
    'killSystemProcess': '终止系统进程（需确认）',
    'confirmKillSystemProcess': '终止系统进程？',
    'confirmKillSystemProcessMsg': '进程 {pid}（用户: {user}）是系统进程，确定要终止吗？',
    'kill': '终止',
    'killFailed': '终止进程失败',
    'sortByCpu': 'CPU 使用率',
    'sortByMem': '内存使用率',
    'sortByMemSize': '内存大小 (RSS)',
    'sortByPid': 'PID',
    'sortByUser': '用户',
    'user': '用户',
    'memSize': 'RSS',
    'processSentSignal': '已发送 SIGTERM 到进程 {pid}',
    'diskCleanup': '磁盘清理',
    'totalCleanable': '可清理总量',
    'quickClean': '快速清理',
    'tempFileBrowser': '临时文件浏览',
    'clean': '清理',
    'cleanAll': '全部清理',
    'cleanAllMsg': '确定清理所有垃圾文件？共 {size}',
    'cleanCompleted': '已清理: {label}',
    'cleanFailed': '清理失败',
    'confirmClean': '确认清理？',
    'scanTempFiles': '扫描临时文件',
    'scanTempFilesDesc': '扫描 /tmp、日志和缓存中的大文件',
    'scan': '扫描',
    'rescan': '重新扫描',
    'confirmDeleteSelected': '删除所选？',
    'confirmDeleteSelectedMsg': '删除选中的 {count} 个文件？',
    'deletedFiles': '已删除 {count} 个文件',
    'deleteFailed': '删除失败',
    'recentLogins': '最近登录',
    'noLoginHistory': '无登录记录',
    'failedLogins': '失败登录',
    'noFailedLogins': '最近7天无失败登录记录',
    'uninstallFromSystem': '卸载',
    'uninstallSuccess': '卸载成功',
    'uninstallFailed': '卸载失败',
    'confirmUninstall': '确认卸载',
    'confirmUninstallMsg': '将从系统中移除应用程序，是否继续？',
    'systemIntegration': '系统集成',
    'newTab': '新建标签页',
    'noSessions': '无会话',
    'closeTab': '关闭标签页',
    'closeOtherTabs': '关闭其他标签页',
    'closeAllTabs': '关闭所有标签页',
    'showWindow': '显示窗口',
    'hideWindow': '隐藏窗口',
    'quit': '退出',
    'uploading': '上传中',
    'batchUpload': '批量上传',
    'uploadFiles': '上传文件',
    'uploadFolders': '上传文件夹',
    'filesReady': '{count} 个文件待上传',
    'uploadingFile': '正在上传: {file}',
    'uploadCompleted': '上传完成',
    'uploadFailed': '上传失败',
    'skipFailed': '跳过失败',
    'retryFailed': '重试失败项',
    'creatingFolders': '正在创建文件夹...',
    'dragFilesOrFoldersHere': '拖拽文件或文件夹到此处上传',
    'transferSpeed': '速度',
    'estimatedTime': '剩余时间',
    'fileProgress': '当前文件',
    'totalProgress': '总进度',
    'waiting': '等待中...',
    'shareDatabase': '分享数据库',
    'about': '关于',
    'featuresAndUsage': '功能与使用说明',
    'aboutUs': '关于我们',
    'version': '版本',
    'developer': '开发者',
    'contactUs': '联系我们',
    'openSourceLicenses': '开源许可',
    'website': '官方网站',
    'shop': '一个小店',
    'uniqueId': '唯一 ID',
    'uniqueIdCopied': 'ID 已复制到剪贴板',
    'buildTime': '构建时间',
    'fileConflictTitleCopy': '文件冲突',
    'fileConflictTitleMove': '文件冲突',
    'fileConflictTitleUpload': '文件冲突',
    'fileConflictMessageCopy': '目标位置已存在同名文件，如何处理？',
    'fileConflictMessageMove': '目标位置已存在同名文件，如何处理？',
    'fileConflictMessageUpload': '服务器上已存在同名文件，如何处理？',
    'overwriteAll': '全部覆盖',
    'renameAll': '全部重命名',
    'skipAll': '全部跳过',
    'directory': '文件夹',
    'checkForUpdates': '检查更新',
    'checkingForUpdate': '正在检查更新...',
    'newVersionAvailable': '发现新版本',
    'noUpdatesAvailable': '暂无更新',
    'currentVersionIsLatest': '当前已是最新版本。',
    'updateCheckFailed': '检查更新失败',
    'unknownError': '发生未知错误。',
    'downloadNow': '下载',
    'updateNow': '更新',
    'openLink': '打开链接',
    'downloadingUpdate': '正在下载更新...',
    'downloadComplete': '下载完成',
    'downloadCompleteMsg': '更新已下载完成，点击「安装」开始安装。',
    'installNow': '安装',
    'skip': '跳过',
    'forceUpdateRequired': '需要强制更新',
    'forceUpdateMessage': '此更新为强制更新，必须更新后才能继续使用。',
    'changelog': '更新日志',
    'releaseDate': '发布日期',
    'fileSize': '文件大小',
  };
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'zh'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
