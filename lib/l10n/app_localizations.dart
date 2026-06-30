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
