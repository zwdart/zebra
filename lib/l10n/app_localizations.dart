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
  String get storage => translate('storage');
  String get storageInfo => translate('storageInfo');
  String get processorCores => translate('processorCores');
  String get hostName => translate('hostName');
  String get cachePath => translate('cachePath');
  String get databasePathLabel => translate('databasePathLabel');
  String get localStoragePath => translate('localStoragePath');
  String get rssDownloadPath => translate('rssDownloadPath');
  String get clearRunningData => translate('clearRunningData');
  String get clearAllData => translate('clearAllData');
  String get clearRunningDataMsg => translate('clearRunningDataMsg');
  String get clearAllDataMsg => translate('clearAllDataMsg');
  String get clearSuccess => translate('clearSuccess');
  String get clearFailed => translate('clearFailed');
  String get close => translate('close');
  String get back => translate('back');
  String get exitSftp => translate('exitSftp');
  String get minimize => translate('minimize');
  String get monitor => translate('monitor');
  String get edit => translate('edit');
  String get view => translate('view');
  String get scanning => translate('scanning');
  String errorWithDetail(String detail) => translate('errorWithDetail').replaceAll('{detail}', detail);
  String sftpErrorWithDetail(String detail) => translate('sftpError').replaceAll('{detail}', detail);
  String get cannotReadFile => translate('cannotReadFile');
  String get failedToLoadFile => translate('failedToLoadFile');
  String get noDiscoveryItems => translate('noDiscoveryItems');
  String fileSaved(String name) => translate('fileSaved').replaceAll('{name}', name);
  String deleteFolderConfirm(String name) => translate('deleteFolderConfirm').replaceAll('{name}', name);
  String deleteFilesConfirm(int count) => translate('deleteFilesConfirm').replaceAll('{count}', '$count');
  String get apiServer => translate('apiServer');
  String get apiBaseUrl => translate('apiBaseUrl');
  String get apiUrlResetDefault => translate('apiUrlResetDefault');
  String apiUrlUpdated(String url) => translate('apiUrlUpdated').replaceAll('{url}', url);
  String get shareDatabases => translate('shareDatabases');
  String readOnlyPreview(String size) => translate('readOnlyPreview').replaceAll('{size}', size);
  String get databaseDirNotFound => translate('databaseDirNotFound');
  String get noDatabaseFiles => translate('noDatabaseFiles');
  String get api => translate('api');
  String maxTabsReached(int count) => translate('maxTabsReached').replaceAll('{count}', '$count');
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
  String get feedback => translate('feedback');
  String get feedbackEmail => translate('feedbackEmail');
  String get feedbackEmailRequired => translate('feedbackEmailRequired');
  String get feedbackEmailInvalid => translate('feedbackEmailInvalid');
  String get feedbackSubject => translate('feedbackSubject');
  String get feedbackSubjectRequired => translate('feedbackSubjectRequired');
  String get feedbackDescription => translate('feedbackDescription');
  String get feedbackDescriptionRequired => translate('feedbackDescriptionRequired');
  String get feedbackSubmit => translate('feedbackSubmit');
  String get feedbackSubmitSuccess => translate('feedbackSubmitSuccess');
  String get feedbackSubmitFailed => translate('feedbackSubmitFailed');
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
  String get downloadPathLabel => translate('downloadPathLabel');
  String get openFolder => translate('openFolder');
  String get installNow => translate('installNow');
  String get skip => translate('skip');
  String get forceUpdateRequired => translate('forceUpdateRequired');
  String get forceUpdateMessage => translate('forceUpdateMessage');
  String get changelog => translate('changelog');
  String get releaseDate => translate('releaseDate');
  String get fileSize => translate('fileSize');

  // Discovery
  String get discover => translate('discover');
  String get discoveryTypeOfficial => translate('discoveryTypeOfficial');
  String get discoveryTypeRecommended => translate('discoveryTypeRecommended');
  String get discoveryTypeAd => translate('discoveryTypeAd');
  String get discoverySortOrder => translate('discoverySortOrder');
  String get discoverySortTime => translate('discoverySortTime');
  String get discoverySortHot => translate('discoverySortHot');
  String get discoveryRandom => translate('discoveryRandom');
  String get discoveryFilterAll => translate('discoveryFilterAll');
  String get discoveryTotal => translate('discoveryTotal');
  String get discoveryEmpty => translate('discoveryEmpty');

  // Linux Commands
  String get linuxCommands => translate('linuxCommands');
  String get linuxCommandsManage => translate('linuxCommandsManage');
  String get command => translate('command');
  String get commandDescriptionZh => translate('commandDescriptionZh');
  String get commandDescriptionEn => translate('commandDescriptionEn');
  String get exportCsv => translate('exportCsv');
  String get importCsv => translate('importCsv');
  String get resetToDefault => translate('resetToDefault');
  String get addCommand => translate('addCommand');
  String get editCommand => translate('editCommand');
  String get deleteCommandConfirm => translate('deleteCommandConfirm');
  String get commandCopied => translate('commandCopied');
  String get noCommands => translate('noCommands');
  String get importSuccess => translate('importSuccess');
  String get importFailed => translate('importFailed');
  String get exportSuccess => translate('exportSuccess');
  String get exportFailed => translate('exportFailed');
  String get totalCommands => translate('totalCommands');
  String get usageExamples => translate('usageExamples');

  // Diary
  String get diary => translate('diary');
  String get diaryEmpty => translate('diaryEmpty');
  String get diaryTitle => translate('diaryTitle');
  String get diaryContent => translate('diaryContent');
  String get diaryMood => translate('diaryMood');
  String get diaryNew => translate('diaryNew');
  String get diaryEdit => translate('diaryEdit');
  String get diaryDeleteConfirm => translate('diaryDeleteConfirm');
  String get diaryMoodHappy => translate('diaryMoodHappy');
  String get diaryMoodNeutral => translate('diaryMoodNeutral');
  String get diaryMoodSad => translate('diaryMoodSad');
  String get diaryMoodAngry => translate('diaryMoodAngry');
  String get diaryMoodExcited => translate('diaryMoodExcited');
  String get diaryExportCsv => translate('diaryExportCsv');
  String get diaryImportCsv => translate('diaryImportCsv');
  String get diaryImportSuccess => translate('diaryImportSuccess');
  String get diaryImportFailed => translate('diaryImportFailed');
  String get diaryExportSuccess => translate('diaryExportSuccess');
  String get diaryExportFailed => translate('diaryExportFailed');

  // Blog
  String get blog => translate('blog');
  String get blogEmpty => translate('blogEmpty');
  String get blogTotal => translate('blogTotal');
  String get share => translate('share');
  String get openInBrowser => translate('openInBrowser');
  String get copyLink => translate('copyLink');
  String get linkCopied => translate('linkCopied');

  // RSS
  String get rssSubscription => translate('rssSubscription');
  String get rssFeedManagement => translate('rssFeedManagement');
  String get rssFolderManagement => translate('rssFolderManagement');
  String get rssSettings => translate('rssSettings');
  String get rssSyncAll => translate('rssSyncAll');
  String get rssSyncing => translate('rssSyncing');
  String get rssSyncComplete => translate('rssSyncComplete');
  String get rssNoSources => translate('rssNoSources');
  String get rssAddSource => translate('rssAddSource');
  String get rssAddSourceHint => translate('rssAddSourceHint');
  String get rssOneClickAdd => translate('rssOneClickAdd');
  String get rssNoArticles => translate('rssNoArticles');
  String get rssNoArticlesHint => translate('rssNoArticlesHint');
  String get rssSyncNow => translate('rssSyncNow');
  String get rssRecommended => translate('rssRecommended');
  String get rssManualAdd => translate('rssManualAdd');
  String get rssImportCsv => translate('rssImportCsv');
  String get rssImportOpml => translate('rssImportOpml');
  String get rssExportCsv => translate('rssExportCsv');
  String get rssExportOpml => translate('rssExportOpml');
  String get rssImportCsvDesc => translate('rssImportCsvDesc');
  String get rssImportOpmlDesc => translate('rssImportOpmlDesc');
  String get rssExportCsvDesc => translate('rssExportCsvDesc');
  String get rssExportOpmlDesc => translate('rssExportOpmlDesc');
  String get rssImportComplete => translate('rssImportComplete');
  String get rssExportSuccess => translate('rssExportSuccess');
  String get rssFileSavedTo => translate('rssFileSavedTo');
  String get rssClose => translate('rssClose');
  String get rssExportFailed => translate('rssExportFailed');
  String get rssCreateFolder => translate('rssCreateFolder');
  String get rssEditFolder => translate('rssEditFolder');
  String get rssDeleteFolder => translate('rssDeleteFolder');
  String get rssDeleteFolderConfirm => translate('rssDeleteFolderConfirm');
  String get rssFolderName => translate('rssFolderName');
  String get rssFolderDesc => translate('rssFolderDesc');
  String get rssFolderDescOptional => translate('rssFolderDescOptional');
  String get rssFolderEmpty => translate('rssFolderEmpty');
  String get rssFolderEmptyHint => translate('rssFolderEmptyHint');
  String get rssNoFolders => translate('rssNoFolders');
  String get rssNoFoldersHint => translate('rssNoFoldersHint');
  String get rssSourcesCount => translate('rssSourcesCount');
  String get rssSelectedCount => translate('rssSelectedCount');
  String get rssSelectAll => translate('rssSelectAll');
  String get rssRemoveFromFolder => translate('rssRemoveFromFolder');
  String get rssRemoveConfirm => translate('rssRemoveConfirm');
  String get rssBatchRemove => translate('rssBatchRemove');
  String get rssBatchRemoveConfirm => translate('rssBatchRemoveConfirm');
  String get rssRemoved => translate('rssRemoved');
  String get rssAddToLocal => translate('rssAddToLocal');
  String get rssAddByUrl => translate('rssAddByUrl');
  String get rssBatchDelete => translate('rssBatchDelete');
  String get rssRefreshList => translate('rssRefreshList');
  String get rssSourceEmpty => translate('rssSourceEmpty');
  String get rssSourceEmptyHint => translate('rssSourceEmptyHint');
  String get rssViewArticle => translate('rssViewArticle');
  String get rssArticleDetail => translate('rssArticleDetail');
  String get rssCopyLink => translate('rssCopyLink');
  String get rssLinkCopied => translate('rssLinkCopied');
  String get rssMarkAsRead => translate('rssMarkAsRead');
  String get rssMarkAsUnread => translate('rssMarkAsUnread');
  String get rssDeleteArticle => translate('rssDeleteArticle');
  String get rssDeleteArticleConfirm => translate('rssDeleteArticleConfirm');
  String get rssArticleDeleted => translate('rssArticleDeleted');
  String get rssOriginal => translate('rssOriginal');
  String get rssRendered => translate('rssRendered');
  String get rssHidden => translate('rssHidden');
  String get rssRaw => translate('rssRaw');
  String get rssExpand => translate('rssExpand');
  String get rssCollapse => translate('rssCollapse');
  String get rssOriginalLink => translate('rssOriginalLink');
  String get rssViewInBrowser => translate('rssViewInBrowser');
  String get rssNoLink => translate('rssNoLink');
  String get rssRecommendedSources => translate('rssRecommendedSources');
  String get rssBatchAdd => translate('rssBatchAdd');
  String get rssMaxSelect => translate('rssMaxSelect');
  String get rssViewingFolder => translate('rssViewingFolder');
  String get rssFetchFromServer => translate('rssFetchFromServer');
  String get rssTotalCount => translate('rssTotalCount');
  String get rssAddToFolder => translate('rssAddToFolder');
  String get rssAddedToFolder => translate('rssAddedToFolder');
  String get rssNoFoldersAvailable => translate('rssNoFoldersAvailable');
  String get rssSyncInterval => translate('rssSyncInterval');
  String get rssSyncIntervalDesc => translate('rssSyncIntervalDesc');
  String get rssSyncIntervalMin => translate('rssSyncIntervalMin');
  String get rssHistoryCleanup => translate('rssHistoryCleanup');
  String get rssClean7Days => translate('rssClean7Days');
  String get rssClean7DaysDesc => translate('rssClean7DaysDesc');
  String get rssClean30Days => translate('rssClean30Days');
  String get rssClean30DaysDesc => translate('rssClean30DaysDesc');
  String get rssCleanAll => translate('rssCleanAll');
  String get rssCleanAllDesc => translate('rssCleanAllDesc');
  String get rssCleanConfirm => translate('rssCleanConfirm');
  String get rssCleanDaysAgo => translate('rssCleanDaysAgo');
  String get rssCleanedAll => translate('rssCleanedAll');
  String get rssMarkAllRead => translate('rssMarkAllRead');
  String get rssMarkedAllRead => translate('rssMarkedAllRead');
  String get rssClearArticles => translate('rssClearArticles');
  String get rssClearArticlesConfirm => translate('rssClearArticlesConfirm');
  String get rssArticlesCleared => translate('rssArticlesCleared');
  String get rssBackToHome => translate('rssBackToHome');
  String get rssUnread => translate('rssUnread');
  String get rssSyncingAll => translate('rssSyncingAll');
  String get rssSyncingFolder => translate('rssSyncingFolder');
  String get rssSyncingSource => translate('rssSyncingSource');
  String get rssSyncedCount => translate('rssSyncedCount');
  String get rssAddToFolderTitle => translate('rssAddToFolderTitle');
  String get rssFeedUrl => translate('rssFeedUrl');
  String get rssFeedTitle => translate('rssFeedTitle');
  String get rssFeedTitleHint => translate('rssFeedTitleHint');
  String get rssFeedType => translate('rssFeedType');
  String get rssFeedCategory => translate('rssFeedCategory');
  String get rssFeedEnabled => translate('rssFeedEnabled');
  String get rssSave => translate('rssSave');
  String get rssEditSource => translate('rssEditSource');
  String get rssDeleteSource => translate('rssDeleteSource');
  String get rssDeleteSourceConfirm => translate('rssDeleteSourceConfirm');
  String get rssDeleteSourceArticles => translate('rssDeleteSourceArticles');
  String get rssSourceInFolders => translate('rssSourceInFolders');
  String get rssSourceRemovedFromFolders => translate('rssSourceRemovedFromFolders');
  String get rssSourceDeleted => translate('rssSourceDeleted');
  String get rssSyncSource => translate('rssSyncSource');
  String get rssSourceInfo => translate('rssSourceInfo');
  String get rssType => translate('rssType');
  String get rssSite => translate('rssSite');
  String get rssLastSync => translate('rssLastSync');
  String get rssSyncError => translate('rssSyncError');
  String get rssSearchSources => translate('rssSearchSources');
  String get rssNoAddableSources => translate('rssNoAddableSources');
  String get rssAddFromLocal => translate('rssAddFromLocal');
  String get rssAddCount => translate('rssAddCount');
  String get rssAddedCount => translate('rssAddedCount');
  String get rssMarkAllReadConfirm => translate('rssMarkAllReadConfirm');
  String get rssFeedExists => translate('rssFeedExists');
  String get rssAddFailed => translate('rssAddFailed');
  String get rssAddFailedCheckUrl => translate('rssAddFailedCheckUrl');
  String get rssSyncFailed => translate('rssSyncFailed');
  String get rssFeedAddedToFolder => translate('rssFeedAddedToFolder');

  // About
  String get aboutSlogan => translate('aboutSlogan');
  String get aboutDescription => translate('aboutDescription');
  String get emailCopied => translate('emailCopied');
  String get featureSshTerminal => translate('featureSshTerminal');
  String get featureSshTerminalDesc => translate('featureSshTerminalDesc');
  String get featureSftp => translate('featureSftp');
  String get featureSftpDesc => translate('featureSftpDesc');
  String get featureMonitor => translate('featureMonitor');
  String get featureMonitorDesc => translate('featureMonitorDesc');
  String get featureProcess => translate('featureProcess');
  String get featureProcessDesc => translate('featureProcessDesc');
  String get featureCleanup => translate('featureCleanup');
  String get featureCleanupDesc => translate('featureCleanupDesc');
  String get featureTheme => translate('featureTheme');
  String get featureThemeDesc => translate('featureThemeDesc');
  String get featureBackup => translate('featureBackup');
  String get featureBackupDesc => translate('featureBackupDesc');

  // Starred/Favorites
  String get rssFavorites => translate('rssFavorites');

  // Discovery pagination
  String get discoverySearchHint => translate('discoverySearchHint');
  String get discoverySearch => translate('discoverySearch');
  String get discoveryFirstPage => translate('discoveryFirstPage');
  String get discoveryPrevPage => translate('discoveryPrevPage');
  String get discoveryNextPage => translate('discoveryNextPage');
  String get discoveryLastPage => translate('discoveryLastPage');
  String get discoveryPage => translate('discoveryPage');
  String get discoveryJumpTo => translate('discoveryJumpTo');
  String get discoveryShare => translate('discoveryShare');
  String get discoveryOpenBrowser => translate('discoveryOpenBrowser');
  String get discoveryCopy => translate('discoveryCopy');
  String get discoveryCopied => translate('discoveryCopied');

  // RSS Explore
  String get rssExplore => translate('rssExplore');

  // Image error
  String get imageLoadFailed => translate('imageLoadFailed');

  // RSS Settings
  String get rssCleanDaysConfirm => translate('rssCleanDaysConfirm');
  String get rssCleanAllConfirm => translate('rssCleanAllConfirm');

  // Feedback
  String get feedbackDescriptionHint => translate('feedbackDescriptionHint');
  String get feedbackHint => translate('feedbackHint');
  String get feedbackNote => translate('feedbackNote');

  // Blog
  String get blogPage => translate('blogPage');

  // Diary
  String get diaryImportPath => translate('diaryImportPath');
  String get diaryNoTitle => translate('diaryNoTitle');

  // Parameterized RSS helpers
  String rssDeleteFolderConfirmValue(String name) {
    return translate('rssDeleteFolderConfirm').replaceAll('{name}', name);
  }
  String rssSourcesCountValue(int count) {
    return translate('rssSourcesCount').replaceAll('{count}', '$count');
  }
  String rssSelectedCountValue(int count) {
    return translate('rssSelectedCount').replaceAll('{count}', '$count');
  }
  String rssSyncedCountValue(int count) {
    return translate('rssSyncedCount').replaceAll('{count}', '$count');
  }
  String rssSyncingSourceValue(String name) {
    return translate('rssSyncingSource').replaceAll('{name}', name);
  }
  String rssRemoveConfirmValue(String name) {
    return translate('rssRemoveConfirm').replaceAll('{name}', name);
  }
  String rssBatchRemoveConfirmValue(int count) {
    return translate('rssBatchRemoveConfirm').replaceAll('{count}', '$count');
  }
  String rssAddedCountValue(int count) {
    return translate('rssAddedCount').replaceAll('{count}', '$count');
  }
  String rssBatchAddValue(int count) {
    return translate('rssBatchAdd').replaceAll('{count}', '$count');
  }
  String get terminalNotAvailable => translate('terminalNotAvailable');
  String get copiedToClipboard => translate('copiedToClipboard');
  String get importExport => translate('importExport');
  String get importFeeds => translate('importFeeds');
  String get exportFeeds => translate('exportFeeds');
  String get more => translate('more');

  // LAN Chat
  String get chat => translate('chat');
  String get lanChat => translate('lanChat');
  String get lanChatSubtitle => translate('lanChatSubtitle');
  String get discoveryPort => translate('discoveryPort');
  String get discoveryPortSubtitle => translate('discoveryPortSubtitle');
  String get discoveryPortHint => translate('discoveryPortHint');
  String discoveryPortDescriptionValue(int defaultValue) =>
      translate('discoveryPortDescription').replaceAll('{default}', '$defaultValue');
  String get discoveryPortInvalid => translate('discoveryPortInvalid');
  String get chatHistory => translate('chatHistory');
  String get deviceList => translate('deviceList');
  String get viewDetail => translate('viewDetail');
  String get messageDetail => translate('messageDetail');
  String get copied => translate('copied');
  String get fileNotShareable => translate('fileNotShareable');
  String get fileInfoMissing => translate('fileInfoMissing');
  String get multiSelect => translate('multiSelect');
  String get mergeShare => translate('mergeShare');
  String get deleteMessages => translate('deleteMessages');
  String get confirmDeleteMessage => translate('confirmDeleteMessage');
  String confirmDeleteMessagesValue(int count) =>
      translate('confirmDeleteMessages').replaceAll('{count}', '$count');
  String selectedCountValue(int count) =>
      translate('selectedCount').replaceAll('{count}', '$count');
  String get deleteDevice => translate('deleteDevice');
  String confirmDeleteDeviceValue(String name, String addr) {
    return translate('confirmDeleteDevice')
        .replaceAll('{name}', name)
        .replaceAll('{addr}', addr);
  }
  String get fileDefaultName => translate('fileDefaultName');
  String get viewFolderHint => translate('viewFolderHint');
  String get cannotOpenDownloads => translate('cannotOpenDownloads');
  String get downloadsUnavailable => translate('downloadsUnavailable');
  String get cannotOpenFolder => translate('cannotOpenFolder');
  String get openFolderFailed => translate('openFolderFailed');
  String get discoveryPortNonDefault => translate('discoveryPortNonDefault');
  String discoveryPortWarningValue(int configured, int defaultValue) {
    return translate('discoveryPortWarning')
        .replaceAll('{configured}', '$configured')
        .replaceAll('{default}', '$defaultValue');
  }
  String get gotIt => translate('gotIt');
  String get resetNow => translate('resetNow');
  String get discoveryPortReset => translate('discoveryPortReset');
  String get localInfo => translate('localInfo');
  String get localInfoIp => translate('localInfoIp');
  String get localInfoPort => translate('localInfoPort');
  String get localInfoDeviceName => translate('localInfoDeviceName');
  String get editNickname => translate('editNickname');
  String get changeNickname => translate('changeNickname');
  String get nicknameHint => translate('nicknameHint');
  String get nicknameNotEmpty => translate('nicknameNotEmpty');
  String nicknameUpdatedValue(String name) =>
      translate('nicknameUpdated').replaceAll('{name}', name);
  String discoveryStartFailedValue(String error) =>
      translate('discoveryStartFailed').replaceAll('{error}', error);
  String get deleteChatHistory => translate('deleteChatHistory');
  String confirmDeleteChatHistoryValue(String name) =>
      translate('confirmDeleteChatHistory').replaceAll('{name}', name);
  String get connected => translate('connected');
  String get disconnected => translate('disconnected');
  String get chatDetails => translate('chatDetails');
  String get peerDevice => translate('peerDevice');
  String get localDevice => translate('localDevice');
  String get deviceName => translate('deviceName');
  String get ipAddress => translate('ipAddress');
  String get portNumber => translate('portNumber');
  String get sendFile => translate('sendFile');
  String get send => translate('send');
  String get reconnect => translate('reconnect');
  String get startChat => translate('startChat');
  String get pickingFiles => translate('pickingFiles');
  String preparingFiles(int count) {
    return translate('preparingFiles').replaceAll('{count}', '$count');
  }
  String get messageHint => translate('messageHint');
  String get transferPending => translate('transferPending');
  String get transferTransferring => translate('transferTransferring');
  String get transferPaused => translate('transferPaused');
  String get transferPause => translate('transferPause');
  String get transferResume => translate('transferResume');
  String get transferDone => translate('transferDone');
  String get transferFailed => translate('transferFailed');
  String get transferCancelled => translate('transferCancelled');
  String get remainingTimeLabel => translate('remainingTimeLabel');
  String get elapsedTimeLabel => translate('elapsedTimeLabel');
  String get enableDiscovery => translate('enableDiscovery');
  String get disableDiscovery => translate('disableDiscovery');
  String get enableDiscoveryHint => translate('enableDiscoveryHint');
  String lastStartFailedValue(String error) =>
      translate('lastStartFailed').replaceAll('{error}', error);
  String get searchingDevices => translate('searchingDevices');
  String get noChatHistory => translate('noChatHistory');
  String get waitingForPeer => translate('waitingForPeer');
  String get timeJustNow => translate('timeJustNow');
  String timeMinutesAgoValue(int minutes) =>
      translate('timeMinutesAgo').replaceAll('{minutes}', '$minutes');

  // QR Tool
  String get qrTool => translate('qrTool');
  String get qrGenerate => translate('qrGenerate');
  String get qrRecognize => translate('qrRecognize');
  String get qrContent => translate('qrContent');
  String get qrContentHint => translate('qrContentHint');
  String get qrSave => translate('qrSave');
  String get qrShare => translate('qrShare');
  String get qrBasicSettings => translate('qrBasicSettings');
  String get qrErrorLevel => translate('qrErrorLevel');
  String get qrErrorLevelLow => translate('qrErrorLevelLow');
  String get qrErrorLevelMedium => translate('qrErrorLevelMedium');
  String get qrErrorLevelQuartile => translate('qrErrorLevelQuartile');
  String get qrErrorLevelHigh => translate('qrErrorLevelHigh');
  String get qrForeground => translate('qrForeground');
  String get qrBackground => translate('qrBackground');
  String get qrAdvancedSettings => translate('qrAdvancedSettings');
  String get qrShape => translate('qrShape');
  String get qrShapeSquares => translate('qrShapeSquares');
  String get qrShapeSmooth => translate('qrShapeSmooth');
  String get qrShapeDots => translate('qrShapeDots');
  String get qrShapeRounded => translate('qrShapeRounded');
  String get qrGradient => translate('qrGradient');
  String get qrGradientStart => translate('qrGradientStart');
  String get qrGradientEnd => translate('qrGradientEnd');
  String get qrCustomColor => translate('qrCustomColor');
  String get qrCustomColorDesc => translate('qrCustomColorDesc');
  String get qrQuietZone => translate('qrQuietZone');
  String get qrDensity => translate('qrDensity');
  String get qrRounding => translate('qrRounding');
  String get qrLogo => translate('qrLogo');
  String get qrNoLogo => translate('qrNoLogo');
  String get qrLogoSet => translate('qrLogoSet');
  String get qrLogoErrorLevelHint => translate('qrLogoErrorLevelHint');
  String get qrPickLogo => translate('qrPickLogo');
  String get qrRemoveLogo => translate('qrRemoveLogo');
  String get qrSavedToGallery => translate('qrSavedToGallery');
  String get qrSaveSuccess => translate('qrSaveSuccess');
  String get qrSaveFailed => translate('qrSaveFailed');
  String get qrShareFailed => translate('qrShareFailed');
  String get qrPickImage => translate('qrPickImage');
  String get qrDragHint => translate('qrDragHint');
  String get qrNoResult => translate('qrNoResult');
  String get qrDecodeResult => translate('qrDecodeResult');
  String get qrDecodeTime => translate('qrDecodeTime');
  String get qrDecodeFailed => translate('qrDecodeFailed');

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
    'storage': 'Storage Space',
    'storageInfo': 'Storage Info',
    'processorCores': 'CPU Cores',
    'hostName': 'Host Name',
    'cachePath': 'Cache Path',
    'databasePathLabel': 'Database Path',
    'localStoragePath': 'Local Storage Path',
    'rssDownloadPath': 'RSS Download Path',
    'clearRunningData': 'Clear Running Data',
    'clearAllData': 'Clear All Data',
    'clearRunningDataMsg': 'This will clear temporary cache files. Continue?',
    'clearAllDataMsg': 'This will clear all cache and database data. This cannot be undone. Continue?',
    'clearSuccess': 'Cleared successfully',
    'clearFailed': 'Clear failed',
    'close': 'Close',
    'back': 'Back',
    'exitSftp': 'Exit SFTP',
    'minimize': 'Minimize',
    'monitor': 'Monitor',
    'edit': 'Edit',
    'view': 'View',
    'scanning': 'Scanning...',
    'errorWithDetail': 'Error: {detail}',
    'sftpError': 'SFTP error: {detail}',
    'cannotReadFile': 'Cannot read file',
    'failedToLoadFile': 'Failed to load file',
    'noDiscoveryItems': 'No discovery items available',
    'fileSaved': '{name} saved',
    'deleteFolderConfirm': 'Delete "{name}" and all its contents?',
    'deleteFilesConfirm': 'Delete {count} files?',
    'apiServer': 'API Server',
    'apiBaseUrl': 'API Base URL',
    'apiUrlResetDefault': 'API URL reset to default',
    'apiUrlUpdated': 'API URL updated: {url}',
    'shareDatabases': 'Share Databases',
    'readOnlyPreview': 'File size: {size} - Read-only preview',
    'databaseDirNotFound': 'Database directory not found',
    'noDatabaseFiles': 'No database files found',
    'api': 'API',
    'maxTabsReached': 'Maximum {count} tabs reached',
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
    'feedback': 'Feedback',
    'feedbackEmail': 'Email',
    'feedbackEmailRequired': 'Email is required',
    'feedbackEmailInvalid': 'Please enter a valid email',
    'feedbackSubject': 'Subject',
    'feedbackSubjectRequired': 'Subject is required',
    'feedbackDescription': 'Description',
    'feedbackDescriptionRequired': 'Description is required',
    'feedbackSubmit': 'Submit Feedback',
    'feedbackSubmitSuccess': 'Feedback submitted successfully',
    'feedbackSubmitFailed': 'Failed to submit feedback',
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
    'downloadPathLabel': 'Saved to:',
    'openFolder': 'Open Folder',
    'installNow': 'Install',
    'skip': 'Skip',
    'forceUpdateRequired': 'Force Update Required',
    'forceUpdateMessage': 'This update is required. You must update to continue using the app.',
    'changelog': 'Changelog',
    'releaseDate': 'Release Date',
    'fileSize': 'File Size',
    'discover': 'Discover',
    'discoveryTypeOfficial': 'Official',
    'discoveryTypeRecommended': 'Recommended',
    'discoveryTypeAd': 'Ad',
    'discoverySortOrder': 'Sort by Order',
    'discoverySortTime': 'Sort by Time',
    'discoverySortHot': 'Sort by Hot',
    'discoveryRandom': 'Random',
    'discoveryFilterAll': 'All',
    'discoveryTotal': 'Total',
    'discoveryEmpty': 'No discovery items yet',
    'linuxCommands': 'Linux Commands',
    'linuxCommandsManage': 'Manage Linux Commands',
    'command': 'Command',
    'commandDescriptionZh': 'Chinese Description',
    'commandDescriptionEn': 'English Description',
    'exportCsv': 'Export CSV',
    'importCsv': 'Import CSV',
    'resetToDefault': 'Reset to Default',
    'addCommand': 'Add Command',
    'editCommand': 'Edit Command',
    'deleteCommandConfirm': 'Delete this command?',
    'commandCopied': 'Command copied to clipboard',
    'noCommands': 'No commands found',
    'importSuccess': 'Import successful',
    'importFailed': 'Import failed',
    'exportSuccess': 'CSV exported successfully',
    'exportFailed': 'Export failed',
    'totalCommands': 'Total: {count}',
    'usageExamples': 'Usage Examples',
    'diary': 'Diary',
    'diaryEmpty': 'No diary entries yet',
    'diaryTitle': 'Title',
    'diaryContent': 'Content',
    'diaryMood': 'Mood',
    'diaryNew': 'New Entry',
    'diaryEdit': 'Edit Entry',
    'diaryDeleteConfirm': 'Delete this diary entry?',
    'diaryMoodHappy': 'Happy',
    'diaryMoodNeutral': 'Neutral',
    'diaryMoodSad': 'Sad',
    'diaryMoodAngry': 'Angry',
    'diaryMoodExcited': 'Excited',
    'diaryExportCsv': 'Export CSV',
    'diaryImportCsv': 'Import CSV',
    'diaryImportSuccess': 'Import successful',
    'diaryImportFailed': 'Import failed',
    'diaryExportSuccess': 'CSV exported successfully',
    'diaryExportFailed': 'Export failed',
    'blog': 'Blog',
    'blogEmpty': 'No blog posts yet',
    'blogTotal': 'Total',
    'share': 'Share',
    'openInBrowser': 'Open in Browser',
    'copyLink': 'Copy Link',
    'linkCopied': 'Link copied',
    // RSS
    'rssSubscription': 'Subscribed',
    'rssFeedManagement': 'Feeds',
    'rssFolderManagement': 'Folders',
    'rssSettings': 'Settings',
    'rssSyncAll': 'Sync All',
    'rssSyncing': 'Syncing...',
    'rssSyncComplete': 'Sync complete',
    'rssNoSources': 'No feeds yet',
    'rssAddSource': 'Add Feed',
    'rssAddSourceHint': 'Add feeds to see articles here',
    'rssOneClickAdd': 'One-click add recommended feeds',
    'rssNoArticles': 'No articles',
    'rssNoArticlesHint': 'Tap button to fetch latest',
    'rssSyncNow': 'Sync Now',
    'rssRecommended': 'Recommended',
    'rssManualAdd': 'Add URL',
    'rssImportCsv': 'Import CSV',
    'rssImportOpml': 'Import OPML',
    'rssExportCsv': 'Export CSV',
    'rssExportOpml': 'Export OPML',
    'rssImportCsvDesc': 'Import feeds from CSV file',
    'rssImportOpmlDesc': 'Import feeds from OPML file',
    'rssExportCsvDesc': 'Export feeds to CSV file',
    'rssExportOpmlDesc': 'Export feeds to OPML file',
    'rssImportComplete': 'Imported {count} feeds',
    'rssExportSuccess': 'Export successful',
    'rssFileSavedTo': 'Saved to:',
    'rssClose': 'Close',
    'rssExportFailed': 'Export failed',
    'rssCreateFolder': 'New Folder',
    'rssEditFolder': 'Edit Folder',
    'rssDeleteFolder': 'Delete Folder',
    'rssDeleteFolderConfirm': 'Delete "{name}"? Feeds inside will not be deleted.',
    'rssFolderName': 'Name *',
    'rssFolderDesc': 'Description',
    'rssFolderDescOptional': 'Description (optional)',
    'rssFolderEmpty': 'No feeds in this folder',
    'rssFolderEmptyHint': 'Add feeds from local list',
    'rssNoFolders': 'No folders yet',
    'rssNoFoldersHint': 'Create folders to organize feeds',
    'rssSourcesCount': '{count} feeds',
    'rssSelectedCount': '{count} selected',
    'rssSelectAll': 'Select All',
    'rssRemoveFromFolder': 'Remove from folder',
    'rssRemoveConfirm': 'Remove "{name}" from folder?',
    'rssBatchRemove': 'Batch Remove',
    'rssBatchRemoveConfirm': 'Remove {count} feeds from folder?',
    'rssRemoved': 'Removed',
    'rssAddToLocal': 'Add from Local',
    'rssAddByUrl': 'Add URL',
    'rssBatchDelete': 'Batch Delete',
    'rssRefreshList': 'Refresh',
    'rssSourceEmpty': 'No feeds',
    'rssSourceEmptyHint': 'Add from recommended or manually',
    'rssViewArticle': 'View Articles',
    'rssArticleDetail': 'Article Detail',
    'rssCopyLink': 'Copy Link',
    'rssLinkCopied': 'Link copied',
    'rssMarkAsRead': 'Mark as Read',
    'rssMarkAsUnread': 'Mark as Unread',
    'rssDeleteArticle': 'Delete Article',
    'rssDeleteArticleConfirm': 'Delete "{title}"?',
    'rssArticleDeleted': 'Article deleted',
    'rssOriginal': 'Original',
    'rssRendered': 'Rendered',
    'rssHidden': 'Hidden',
    'rssRaw': 'Raw',
    'rssExpand': 'Show More',
    'rssCollapse': 'Show Less',
    'rssOriginalLink': 'Original Link',
    'rssViewInBrowser': 'Open in Browser',
    'rssNoLink': 'No link available',
    'rssRecommendedSources': 'Recommended Feeds',
    'rssBatchAdd': 'Add ({count})',
    'rssMaxSelect': 'Max 10',
    'rssViewingFolder': 'Viewing "{name}"',
    'rssFetchFromServer': 'Fetch from server',
    'rssTotalCount': 'Total: {count}',
    'rssAddToFolder': 'Add to Folder',
    'rssAddedToFolder': 'Added to "{name}"',
    'rssNoFoldersAvailable': 'No folders, create one first',
    'rssSyncInterval': 'Auto Sync Interval',
    'rssSyncIntervalDesc': 'Automatically sync feeds every {min} minutes',
    'rssSyncIntervalMin': '{min} min',
    'rssHistoryCleanup': 'History Cleanup',
    'rssClean7Days': 'Clean 7-day old',
    'rssClean7DaysDesc': 'Delete articles older than 7 days',
    'rssClean30Days': 'Clean 30-day old',
    'rssClean30DaysDesc': 'Delete articles older than 30 days',
    'rssCleanAll': 'Clean All',
    'rssCleanAllDesc': 'Delete all cached articles',
    'rssCleanConfirm': 'Confirm Cleanup',
    'rssCleanDaysAgo': 'Delete articles older than {days} days? This cannot be undone.',
    'rssCleanedAll': 'Cleaned articles older than {days} days',
    'rssMarkAllRead': 'Mark All Read',
    'rssMarkedAllRead': 'All marked as read',
    'rssClearArticles': 'Clear Articles',
    'rssClearArticlesConfirm': 'Clear all articles from "{name}"? This cannot be undone.',
    'rssArticlesCleared': 'Articles cleared',
    'rssBackToHome': 'Back to Home',
    'rssUnread': 'Unread',
    'rssSyncingAll': 'Syncing all feeds...',
    'rssSyncingFolder': 'Syncing folder feeds...',
    'rssSyncingSource': 'Syncing "{name}"...',
    'rssSyncedCount': 'Synced {count} feeds',
    'rssAddToFolderTitle': 'Add to Folder',
    'rssFeedUrl': 'RSS URL *',
    'rssFeedTitle': 'Title',
    'rssFeedTitleHint': 'Leave empty to auto-fetch',
    'rssFeedType': 'Type',
    'rssFeedCategory': 'Category',
    'rssFeedEnabled': 'Enabled',
    'rssSave': 'Save',
    'rssEditSource': 'Edit Feed',
    'rssDeleteSource': 'Delete Feed',
    'rssDeleteSourceConfirm': 'Delete "{title}"? This will also delete all related articles.',
    'rssDeleteSourceArticles': 'This will also delete all related articles.',
    'rssSourceInFolders': 'This feed is also in folders:',
    'rssSourceRemovedFromFolders': 'It will be removed from these folders.',
    'rssSourceDeleted': 'Feed deleted',
    'rssSyncSource': 'Sync',
    'rssSourceInfo': 'Info',
    'rssType': 'Type',
    'rssSite': 'Site',
    'rssLastSync': 'Last Sync',
    'rssSyncError': 'Sync Error',
    'rssSearchSources': 'Search feeds...',
    'rssNoAddableSources': 'No feeds to add',
    'rssAddFromLocal': 'Add from Local',
    'rssAddCount': 'Add ({count})',
    'rssAddedCount': 'Added {count} feeds to folder',
    'rssMarkAllReadConfirm': 'All marked as read',
    'rssFeedExists': 'This feed already exists',
    'rssAddFailed': 'Failed to add feed',
    'rssAddFailedCheckUrl': 'Failed to add feed, please check if the URL is correct',
    'rssSyncFailed': 'Sync failed',
    'rssFeedAddedToFolder': 'Feed added to folder',
    // About
    'aboutSlogan': 'A Helpful SSH Client',
    'aboutDescription': 'Zebra SSH is a cross-platform SSH client with terminal, SFTP file management, server monitoring, process management and disk cleanup features. Supports Linux, macOS, Windows, Android and iOS.',
    'emailCopied': 'Email copied',
    'featureSshTerminal': 'SSH Terminal',
    'featureSshTerminalDesc': 'Connect to remote servers and execute commands. Supports password and key authentication with multi-tab management.',
    'featureSftp': 'SFTP File Manager',
    'featureSftpDesc': 'Browse, upload, download, delete, rename, and compress remote files visually. Supports drag-and-drop and batch operations.',
    'featureMonitor': 'Server Monitor',
    'featureMonitorDesc': 'View real-time CPU, memory, disk, network and other system info with auto-refresh support.',
    'featureProcess': 'Process Manager',
    'featureProcessDesc': 'View and manage system processes. Sort by CPU/memory, kill processes.',
    'featureCleanup': 'Disk Cleanup',
    'featureCleanupDesc': 'Scan and clean temporary files, logs, and cache on the server.',
    'featureTheme': 'Theme & Language',
    'featureThemeDesc': 'Light/Dark/System theme, custom theme colors, Chinese/English language support.',
    'featureBackup': 'Database Backup',
    'featureBackupDesc': 'Share database file for backup on mobile devices.',
    // Starred/Favorites
    'rssFavorites': 'Favorites',
    // Discovery pagination
    'discoverySearchHint': 'Search discovery content...',
    'discoverySearch': 'Search',
    'discoveryFirstPage': 'First',
    'discoveryPrevPage': 'Previous',
    'discoveryNextPage': 'Next',
    'discoveryLastPage': 'Last',
    'discoveryPage': 'Page',
    'discoveryJumpTo': 'Go',
    'discoveryShare': 'Share',
    'discoveryOpenBrowser': 'Open in Browser',
    'discoveryCopy': 'Copy',
    'discoveryCopied': 'Copied',
    // RSS Explore
    'rssExplore': 'Explore',
    // Image error
    'imageLoadFailed': 'Image failed to load',
    // RSS Settings
    'rssCleanDaysConfirm': 'Delete all articles older than {days} days? This cannot be undone.',
    'rssCleanAllConfirm': 'Delete all articles? This cannot be undone.',
    // Feedback
    'feedbackDescriptionHint': 'Please describe your issue or suggestion in detail, including steps, expected results...',
    'feedbackHint': 'Briefly describe your feedback',
    'feedbackNote': 'Note: Only one feedback per email every 30 minutes.',
    // Blog
    'blogPage': 'Page',
    // Diary
    'diaryImportPath': 'Please place diary_import.csv at {path}',
    'diaryNoTitle': '(No title)',
    'terminalNotAvailable': 'Terminal not available',
    'copiedToClipboard': 'Copied to clipboard',
    'importExport': 'Import/Export',
    'importFeeds': 'Import Feeds',
    'exportFeeds': 'Export Feeds',
    'more': 'More',
    // LAN Chat
    'chat': 'Chat',
    'lanChat': 'LAN Chat',
    'lanChatSubtitle': 'Discover devices, P2P chat and file transfer',
    'discoveryPort': 'Discovery Port',
    'discoveryPortSubtitle': 'Port for device discovery; must be the same on all devices',
    'discoveryPortHint': 'Leave blank to restore default port',
    'discoveryPortDescription': 'Default port {default}, used to search for LAN devices. All devices must use the same port.',
    'discoveryPortInvalid': 'Please enter a port number between 1 and 65535',
    'chatHistory': 'Chat History',
    'deviceList': 'Device List',
    'viewDetail': 'View Details',
    'messageDetail': 'Message Details',
    'copied': 'Copied',
    'fileNotShareable': 'The file is not shareable from this device. Open its folder to view it.',
    'fileInfoMissing': 'Missing file information',
    'multiSelect': 'Multi-select',
    'mergeShare': 'Merge & Share',
    'deleteMessages': 'Delete Messages',
    'confirmDeleteMessage': 'Delete this message? This cannot be undone.',
    'confirmDeleteMessages': 'Delete the selected {count} messages? This cannot be undone.',
    'selectedCount': '{count} selected',
    'deleteDevice': 'Delete Device',
    'confirmDeleteDevice': 'Remove "{name}" ({addr}) from the device list?\n\nOnly the list entry is removed; it does not affect the peer. If the device is still online, it will reappear after the next heartbeat.',
    'fileDefaultName': 'File',
    'viewFolderHint': 'Tap to open folder',
    'cannotOpenDownloads': 'Cannot open downloads folder',
    'downloadsUnavailable': 'System file manager unavailable. Please open the "Downloads" folder manually.',
    'cannotOpenFolder': 'Cannot open folder',
    'openFolderFailed': 'Failed to open folder',
    'discoveryPortNonDefault': 'Non-default discovery port',
    'discoveryPortWarning': 'Current discovery port is {configured}, not the default {default}.\n\nAll devices must use the same discovery port, otherwise other clients may not be found. You can ignore this if you confirm others use the same port.',
    'gotIt': 'Got it',
    'resetNow': 'Reset now',
    'discoveryPortReset': 'Discovery port restored to default',
    'localInfo': 'Local Info',
    'localInfoIp': 'IP Address',
    'localInfoPort': 'Port',
    'localInfoDeviceName': 'Device Name',
    'editNickname': 'Edit Nickname',
    'changeNickname': 'Change Nickname',
    'nicknameHint': 'Enter nickname',
    'nicknameNotEmpty': 'Nickname cannot be empty',
    'nicknameUpdated': 'Nickname changed to {name}',
    'discoveryStartFailed': 'Failed to start device discovery: {error}',
    'deleteChatHistory': 'Delete Chat History',
    'confirmDeleteChatHistory': 'Delete chat history with "{name}"? This cannot be undone.',
    'connected': 'Connected',
    'disconnected': 'Disconnected',
    'chatDetails': 'Chat Details',
    'peerDevice': 'Peer Device',
    'localDevice': 'Local Device',
    'deviceName': 'Device Name',
    'ipAddress': 'IP Address',
    'portNumber': 'Port',
    'sendFile': 'Send File',
    'send': 'Send',
    'reconnect': 'Reconnect',
    'preparingFiles': 'Preparing {count} files...',
    'pickingFiles': 'Opening file picker...',
    'startChat': 'Start chatting',
    'messageHint': 'Type a message...',
    'transferPending': 'Pending...',
    'transferTransferring': 'Transferring...',
    'transferPaused': 'Paused',
    'transferPause': 'Pause',
    'transferResume': 'Resume',
    'transferDone': 'Completed',
    'transferFailed': 'Transfer failed',
    'transferCancelled': 'Cancelled',
    'remainingTimeLabel': 'ETA',
    'elapsedTimeLabel': 'Elapsed',
    'enableDiscovery': 'Enable discovery',
    'disableDiscovery': 'Disable discovery',
    'enableDiscoveryHint': 'Tap the WiFi icon in the top-right to enable discovery',
    'lastStartFailed': 'Last start failed: {error}',
    'searchingDevices': 'Searching for LAN devices...',
    'noChatHistory': 'No chat history',
    'waitingForPeer': 'Waiting for the peer to connect...',
    'timeJustNow': 'Just now',
    'timeMinutesAgo': '{minutes} min ago',
    // QR Tool
    'qrTool': 'QR Code',
    'qrGenerate': 'Generate',
    'qrRecognize': 'Recognize',
    'qrContent': 'Content',
    'qrContentHint': 'Enter text, URL, WiFi config, etc.',
    'qrSave': 'Save Image',
    'qrShare': 'Share Image',
    'qrBasicSettings': 'Basic Settings',
    'qrErrorLevel': 'Error Correction',
    'qrErrorLevelLow': 'L (7%)',
    'qrErrorLevelMedium': 'M (15%)',
    'qrErrorLevelQuartile': 'Q (25%)',
    'qrErrorLevelHigh': 'H (30%)',
    'qrForeground': 'Foreground',
    'qrBackground': 'Background',
    'qrAdvancedSettings': 'Advanced Settings',
    'qrShape': 'Shape',
    'qrShapeSquares': 'Squares',
    'qrShapeSmooth': 'Smooth',
    'qrShapeDots': 'Dots',
    'qrShapeRounded': 'Rounded',
    'qrGradient': 'Gradient Fill',
    'qrGradientStart': 'Start Color',
    'qrGradientEnd': 'End Color',
    'qrCustomColor': 'Custom Color',
    'qrCustomColorDesc': 'Choose RGB color values, e.g. 255,0,0',
    'qrQuietZone': 'Quiet Zone',
    'qrDensity': 'Density',
    'qrRounding': 'Rounding',
    'qrLogo': 'Embedded Logo',
    'qrNoLogo': 'No logo',
    'qrLogoSet': 'Logo set',
    'qrLogoErrorLevelHint': 'Logo covers data modules; error correction is raised to Q (25%) automatically',
    'qrPickLogo': 'Pick logo image',
    'qrRemoveLogo': 'Remove logo',
    'qrSavedToGallery': 'Saved to gallery',
    'qrSaveSuccess': 'Image saved to:',
    'qrSaveFailed': 'Save failed',
    'qrShareFailed': 'Share failed',
    'qrPickImage': 'Click to pick an image, or drop it here',
    'qrDragHint': 'Supports PNG / JPG with a QR code',
    'qrNoResult': 'No QR code detected',
    'qrDecodeResult': 'Decoded result:',
    'qrDecodeTime': 'Decoded at:',
    'qrDecodeFailed': 'Decode failed',
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
    'storage': '存储空间',
    'storageInfo': '存储信息',
    'processorCores': '处理器核心',
    'hostName': '主机名',
    'cachePath': '缓存路径',
    'databasePathLabel': '数据库路径',
    'localStoragePath': '本地存储路径',
    'rssDownloadPath': 'RSS 下载路径',
    'clearRunningData': '清理运行数据',
    'clearAllData': '清理全部数据',
    'clearRunningDataMsg': '将清理临时缓存文件，是否继续？',
    'clearAllDataMsg': '将清理所有缓存和数据库数据，此操作不可撤销，是否继续？',
    'clearSuccess': '清理成功',
    'clearFailed': '清理失败',
    'close': '关闭',
    'back': '返回',
    'exitSftp': '退出文件管理',
    'minimize': '最小化',
    'monitor': '监控',
    'edit': '编辑',
    'view': '查看',
    'scanning': '扫描中...',
    'errorWithDetail': '错误：{detail}',
    'sftpError': 'SFTP 错误：{detail}',
    'cannotReadFile': '无法读取文件',
    'failedToLoadFile': '文件加载失败',
    'noDiscoveryItems': '暂无发现内容',
    'fileSaved': '{name} 已保存',
    'deleteFolderConfirm': '删除「{name}」及其全部内容？',
    'deleteFilesConfirm': '删除 {count} 个文件？',
    'apiServer': 'API 服务器',
    'apiBaseUrl': 'API 基础地址',
    'apiUrlResetDefault': 'API 地址已重置为默认值',
    'apiUrlUpdated': 'API 地址已更新：{url}',
    'shareDatabases': '分享数据库',
    'readOnlyPreview': '文件大小：{size} - 只读预览',
    'databaseDirNotFound': '未找到数据库目录',
    'noDatabaseFiles': '未找到数据库文件',
    'api': 'API',
    'maxTabsReached': '已达到最多 {count} 个标签页',
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
    'aboutUs': '关于',
    'version': '版本',
    'developer': '开发者',
    'contactUs': '联系我们',
    'openSourceLicenses': '开源许可',
    'website': '官方网站',
    'shop': '一个小店',
    'uniqueId': '唯一 ID',
    'uniqueIdCopied': 'ID 已复制到剪贴板',
    'buildTime': '构建时间',
    'feedback': '意见反馈',
    'feedbackEmail': '邮箱',
    'feedbackEmailRequired': '请输入邮箱',
    'feedbackEmailInvalid': '请输入有效的邮箱地址',
    'feedbackSubject': '主题',
    'feedbackSubjectRequired': '请输入主题',
    'feedbackDescription': '详细说明',
    'feedbackDescriptionRequired': '请输入详细说明',
    'feedbackSubmit': '提交反馈',
    'feedbackSubmitSuccess': '反馈提交成功',
    'feedbackSubmitFailed': '反馈提交失败',
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
    'downloadPathLabel': '保存路径：',
    'openFolder': '打开目录',
    'installNow': '安装',
    'skip': '跳过',
    'forceUpdateRequired': '需要更新',
    'forceUpdateMessage': '建议更新，更新后继续使用。',
    'changelog': '更新日志',
    'releaseDate': '发布日期',
    'fileSize': '文件大小',
    'discover': '发现',
    'discoveryTypeOfficial': '官方',
    'discoveryTypeRecommended': '推荐',
    'discoveryTypeAd': '广告',
    'discoverySortOrder': '按序号',
    'discoverySortTime': '按时间',
    'discoverySortHot': '按热度',
    'discoveryRandom': '随机',
    'discoveryFilterAll': '全部',
    'discoveryTotal': '共',
    'discoveryEmpty': '暂无发现内容',
    'linuxCommands': 'Linux 常用命令',
    'linuxCommandsManage': '管理 Linux 命令',
    'command': '命令',
    'commandDescriptionZh': '中文说明',
    'commandDescriptionEn': '英文说明',
    'exportCsv': '导出 CSV',
    'importCsv': '导入 CSV',
    'resetToDefault': '恢复默认',
    'addCommand': '添加命令',
    'editCommand': '编辑命令',
    'deleteCommandConfirm': '确定删除此命令？',
    'commandCopied': '命令已复制到剪贴板',
    'noCommands': '暂无命令',
    'importSuccess': '导入成功',
    'importFailed': '导入失败',
    'exportSuccess': 'CSV 导出成功',
    'exportFailed': '导出失败',
    'totalCommands': '共 {count} 条',
    'usageExamples': '使用示例',
    'diary': '日记',
    'diaryEmpty': '暂无日记',
    'diaryTitle': '标题',
    'diaryContent': '内容',
    'diaryMood': '心情',
    'diaryNew': '新建日记',
    'diaryEdit': '编辑日记',
    'diaryDeleteConfirm': '确定删除这条日记？',
    'diaryMoodHappy': '开心',
    'diaryMoodNeutral': '平静',
    'diaryMoodSad': '难过',
    'diaryMoodAngry': '生气',
    'diaryMoodExcited': '兴奋',
    'diaryExportCsv': '导出 CSV',
    'diaryImportCsv': '导入 CSV',
    'diaryImportSuccess': '导入成功',
    'diaryImportFailed': '导入失败',
    'diaryExportSuccess': 'CSV 导出成功',
    'diaryExportFailed': '导出失败',
    'blog': '博客',
    'blogEmpty': '暂无博客文章',
    'blogTotal': '共',
    'share': '分享',
    'openInBrowser': '浏览器打开',
    'copyLink': '复制链接',
    'linkCopied': '链接已复制',
    // RSS
    'rssSubscription': '已订阅',
    'rssFeedManagement': '订阅源',
    'rssFolderManagement': '收藏夹',
    'rssSettings': '设置',
    'rssSyncAll': '同步全部',
    'rssSyncing': '同步中...',
    'rssSyncComplete': '同步完成',
    'rssNoSources': '暂无订阅源',
    'rssAddSource': '添加订阅源',
    'rssAddSourceHint': '添加订阅源后，文章将在此显示',
    'rssOneClickAdd': '一键添加推荐订阅源',
    'rssNoArticles': '暂无文章',
    'rssNoArticlesHint': '点击下方按钮获取最新内容',
    'rssSyncNow': '同步最新',
    'rssRecommended': '订阅源',
    'rssManualAdd': '手动添加',
    'rssImportCsv': '从 CSV 导入',
    'rssImportOpml': '从 OPML 导入',
    'rssExportCsv': '导出为 CSV',
    'rssExportOpml': '导出为 OPML',
    'rssImportCsvDesc': '导入 CSV 格式的订阅源列表',
    'rssImportOpmlDesc': '导入 OPML 格式的订阅源列表',
    'rssExportCsvDesc': '将订阅源导出为 CSV 文件',
    'rssExportOpmlDesc': '将订阅源导出为 OPML 文件',
    'rssImportComplete': '导入完成，新增 {count} 个订阅源',
    'rssExportSuccess': '导出成功',
    'rssFileSavedTo': '文件已保存到：',
    'rssClose': '关闭',
    'rssExportFailed': '导出失败',
    'rssCreateFolder': '新建收藏夹',
    'rssEditFolder': '编辑收藏夹',
    'rssDeleteFolder': '删除收藏夹',
    'rssDeleteFolderConfirm': '确定删除「{name}」？收藏夹内的订阅源不会被删除。',
    'rssFolderName': '名称 *',
    'rssFolderDesc': '描述',
    'rssFolderDescOptional': '描述（可选）',
    'rssFolderEmpty': '收藏夹内暂无订阅源',
    'rssFolderEmptyHint': '从本地订阅源列表添加到收藏夹',
    'rssNoFolders': '暂无收藏夹',
    'rssNoFoldersHint': '创建收藏夹来组织你的订阅源',
    'rssSourcesCount': '{count} 个订阅源',
    'rssSelectedCount': '已选 {count} 项',
    'rssSelectAll': '全选',
    'rssRemoveFromFolder': '从收藏夹移除',
    'rssRemoveConfirm': '确定将「{name}」从收藏夹中移除？',
    'rssBatchRemove': '批量移除',
    'rssBatchRemoveConfirm': '确定将选中的 {count} 个订阅源从收藏夹中移除？',
    'rssRemoved': '已移除',
    'rssAddToLocal': '从本地添加',
    'rssAddByUrl': '手动添加 URL',
    'rssBatchDelete': '批量删除',
    'rssRefreshList': '刷新列表',
    'rssSourceEmpty': '暂无订阅源',
    'rssSourceEmptyHint': '可以从推荐列表一键添加，或手动输入 URL',
    'rssViewArticle': '查看文章',
    'rssArticleDetail': '文章详情',
    'rssCopyLink': '复制链接',
    'rssLinkCopied': '链接已复制',
    'rssMarkAsRead': '标为已读',
    'rssMarkAsUnread': '标为未读',
    'rssDeleteArticle': '删除文章',
    'rssDeleteArticleConfirm': '确定删除「{title}」？',
    'rssArticleDeleted': '文章已删除',
    'rssOriginal': '原文',
    'rssRendered': '渲染',
    'rssHidden': '隐藏',
    'rssRaw': '原文',
    'rssExpand': '展开全文',
    'rssCollapse': '收起',
    'rssOriginalLink': '原文链接',
    'rssViewInBrowser': '浏览器打开',
    'rssNoLink': '没有可用的链接',
    'rssRecommendedSources': '订阅源',
    'rssBatchAdd': '批量添加 ({count})',
    'rssMaxSelect': '最多选 10 个',
    'rssViewingFolder': '正在查看「{name}」内的订阅源',
    'rssFetchFromServer': '从服务器获取推荐订阅源',
    'rssTotalCount': '共 {count} 个',
    'rssAddToFolder': '加入收藏夹',
    'rssAddedToFolder': '已加入「{name}」',
    'rssNoFoldersAvailable': '暂无收藏夹，请先创建',
    'rssSyncInterval': '自动同步间隔',
    'rssSyncIntervalDesc': '每隔 {min} 分钟自动同步一次',
    'rssSyncIntervalMin': '{min} 分钟',
    'rssHistoryCleanup': '历史数据清理',
    'rssClean7Days': '清理 7 天前的文章',
    'rssClean7DaysDesc': '删除 7 天以前的所有文章',
    'rssClean30Days': '清理 30 天前的文章',
    'rssClean30DaysDesc': '删除 30 天以前的所有文章',
    'rssCleanAll': '清理所有文章',
    'rssCleanAllDesc': '删除所有已缓存的文章',
    'rssCleanConfirm': '确认清理',
    'rssCleanDaysAgo': '确定删除 {days} 天前的所有文章？此操作不可撤销。',
    'rssCleanedAll': '已清理 {days} 天前的文章',
    'rssMarkAllRead': '全部标为已读',
    'rssMarkedAllRead': '已全部标为已读',
    'rssClearArticles': '清空文章',
    'rssClearArticlesConfirm': '确定清空「{name}」的所有文章？此操作不可撤销。',
    'rssArticlesCleared': '文章已清空',
    'rssBackToHome': '返回首页',
    'rssUnread': '未读',
    'rssSyncingAll': '正在同步所有订阅源...',
    'rssSyncingFolder': '正在同步收藏夹内所有订阅源...',
    'rssSyncingSource': '正在同步「{name}」...',
    'rssSyncedCount': '已同步 {count} 个订阅源',
    'rssAddToFolderTitle': '加入收藏夹',
    'rssFeedUrl': 'RSS URL *',
    'rssFeedTitle': '标题',
    'rssFeedTitleHint': '留空则自动获取',
    'rssFeedType': '类型',
    'rssFeedCategory': '分类',
    'rssFeedEnabled': '启用',
    'rssSave': '保存',
    'rssEditSource': '编辑订阅源',
    'rssDeleteSource': '删除订阅源',
    'rssDeleteSourceConfirm': '确定删除「{title}」？该操作将同时删除所有相关文章。',
    'rssDeleteSourceArticles': '该操作将同时删除所有相关文章。',
    'rssSourceInFolders': '此源还在以下收藏夹中：',
    'rssSourceRemovedFromFolders': '删除后将从这些收藏夹中移除。',
    'rssSourceDeleted': '订阅源已删除',
    'rssSyncSource': '同步',
    'rssSourceInfo': '详情',
    'rssType': '类型',
    'rssSite': '站点',
    'rssLastSync': '上次同步',
    'rssSyncError': '同步错误',
    'rssSearchSources': '搜索订阅源...',
    'rssNoAddableSources': '没有可添加的订阅源',
    'rssAddFromLocal': '从本地添加',
    'rssAddCount': '添加 ({count})',
    'rssAddedCount': '已添加 {count} 个订阅源到收藏夹',
    'rssMarkAllReadConfirm': '已全部标为已读',
    'rssFeedExists': '该订阅源已存在',
    'rssAddFailed': '添加失败',
    'rssAddFailedCheckUrl': '添加失败，请检查URL是否正确',
    'rssSyncFailed': '同步失败',
    'rssFeedAddedToFolder': '订阅源已添加到收藏夹',
    // About
    'aboutSlogan': '友好的 SSH 客户端',
    'aboutDescription': 'Zebra SSH 是一款跨平台 SSH 客户端，支持终端、SFTP 文件管理、服务器监控、进程管理和磁盘清理等功能。支持 Linux、macOS、Windows、Android 和 iOS。',
    'emailCopied': '邮箱已复制',
    'featureSshTerminal': 'SSH 终端',
    'featureSshTerminalDesc': '连接远程服务器，执行命令。支持密码和密钥认证，多标签页管理。',
    'featureSftp': 'SFTP 文件管理',
    'featureSftpDesc': '可视化浏览、上传、下载、删除、重命名、压缩远程文件。支持拖拽上传和批量操作。',
    'featureMonitor': '服务器监控',
    'featureMonitorDesc': '实时查看 CPU、内存、磁盘、网络等系统信息，支持自动刷新。',
    'featureProcess': '进程管理',
    'featureProcessDesc': '查看和管理系统进程，支持按 CPU/内存排序，可终止进程。',
    'featureCleanup': '磁盘清理',
    'featureCleanupDesc': '扫描并清理服务器上的临时文件、日志和缓存。',
    'featureTheme': '主题与语言',
    'featureThemeDesc': '支持浅色/深色/跟随系统主题，可选择主题颜色，支持中英文切换。',
    'featureBackup': '数据库备份',
    'featureBackupDesc': '在移动端可分享数据库文件进行备份。',
    // Starred/Favorites
    'rssFavorites': '收藏文章',
    // Discovery pagination
    'discoverySearchHint': '搜索发现内容...',
    'discoverySearch': '搜索',
    'discoveryFirstPage': '首页',
    'discoveryPrevPage': '上一页',
    'discoveryNextPage': '下一页',
    'discoveryLastPage': '末页',
    'discoveryPage': '页',
    'discoveryJumpTo': '跳转',
    'discoveryShare': '分享',
    'discoveryOpenBrowser': '跳转链接',
    'discoveryCopy': '复制',
    'discoveryCopied': '已复制',
    // RSS Explore
    'rssExplore': '发现中心',
    // Image error
    'imageLoadFailed': '图片加载失败',
    // RSS Settings
    'rssCleanDaysConfirm': '确定删除 {days} 天前的所有文章？此操作不可撤销。',
    'rssCleanAllConfirm': '确定删除所有文章？此操作不可撤销。',
    // Feedback
    'feedbackDescriptionHint': '请详细描述您的问题或建议，包括操作步骤、期望结果等...',
    'feedbackHint': '简要描述您的反馈',
    'feedbackNote': '提示：30分钟内同一邮箱只能提交一次反馈。',
    // Blog
    'blogPage': '页',
    // Diary
    'diaryImportPath': '请将 diary_import.csv 放到 {path}',
    'diaryNoTitle': '(无标题)',
    'terminalNotAvailable': '终端不可用',
    'copiedToClipboard': '已复制到剪贴板',
    'importExport': '导入/导出',
    'importFeeds': '导入订阅源',
    'exportFeeds': '导出订阅源',
    'more': '更多',
    // LAN Chat
    'chat': '聊天',
    'lanChat': '本地聊天',
    'lanChatSubtitle': '发现设备、P2P 聊天与文件传输',
    'discoveryPort': '发现端口',
    'discoveryPortSubtitle': '搜索设备用端口,需所有设备一致',
    'discoveryPortHint': '留空恢复默认端口',
    'discoveryPortDescription': '默认端口 {default},用于搜索局域网设备,所有设备需保持一致。',
    'discoveryPortInvalid': '请输入 1~65535 之间的端口号',
    'chatHistory': '聊天记录',
    'deviceList': '设备列表',
    'viewDetail': '查看详情',
    'messageDetail': '消息详情',
    'copied': '已复制',
    'fileNotShareable': '文件不在本机可分享的位置,请打开所在文件夹查看',
    'fileInfoMissing': '文件信息缺失',
    'multiSelect': '多选',
    'mergeShare': '合并分享',
    'deleteMessages': '删除消息',
    'confirmDeleteMessage': '确定删除这条消息吗?删除后不可恢复。',
    'confirmDeleteMessages': '确定删除选中的 {count} 条消息吗?删除后不可恢复。',
    'selectedCount': '已选 {count} 条',
    'deleteDevice': '删除设备',
    'confirmDeleteDevice': '确定要从设备列表中移除 "{name}"({addr})吗?\n\n仅移除列表中的条目,不会影响对方。若该设备仍在线,收到下一次心跳后会自动重新出现。',
    'fileDefaultName': '文件',
    'viewFolderHint': '点击查看目录',
    'cannotOpenDownloads': '无法打开下载目录',
    'downloadsUnavailable': '系统文件管理器不可用,请手动打开"下载"目录查看文件。',
    'cannotOpenFolder': '无法打开目录',
    'openFolderFailed': '打开目录失败',
    'discoveryPortNonDefault': '发现端口非默认',
    'discoveryPortWarning': '当前发现端口为 {configured},不是默认端口 {default}。\n\n发现端口需要所有设备一致,否则可能无法正常搜索到本地其他客户端。若确认其他客户端也使用相同端口,可忽略本提示。',
    'gotIt': '知道了',
    'resetNow': '一键重置',
    'discoveryPortReset': '已恢复默认发现端口',
    'localInfo': '本机信息',
    'localInfoIp': 'IP 地址',
    'localInfoPort': '端口号',
    'localInfoDeviceName': '设备名',
    'editNickname': '编辑昵称',
    'changeNickname': '修改昵称',
    'nicknameHint': '请输入昵称',
    'nicknameNotEmpty': '昵称不能为空',
    'nicknameUpdated': '昵称已修改为 {name}',
    'discoveryStartFailed': '无法开启设备发现:{error}',
    'deleteChatHistory': '删除聊天记录',
    'confirmDeleteChatHistory': '确定要删除与 "{name}" 的聊天记录吗?删除后不可恢复。',
    'connected': '已连接',
    'disconnected': '未连接',
    'chatDetails': '对话详情',
    'peerDevice': '对方设备',
    'localDevice': '本机',
    'deviceName': '设备名',
    'ipAddress': 'IP 地址',
    'portNumber': '端口号',
    'sendFile': '发送文件',
    'send': '发送',
    'reconnect': '重新连接',
    'preparingFiles': '正在准备传输 {count} 个文件...',
    'pickingFiles': '正在打开文件选择器...',
    'startChat': '开始聊天吧',
    'messageHint': '输入消息...',
    'transferPending': '等待中...',
    'transferTransferring': '传输中...',
    'transferPaused': '已暂停',
    'transferPause': '暂停',
    'transferResume': '恢复',
    'transferDone': '传输完成',
    'transferFailed': '传输失败',
    'transferCancelled': '已取消',
    'remainingTimeLabel': '剩余',
    'elapsedTimeLabel': '已用',
    'enableDiscovery': '开启发现',
    'disableDiscovery': '关闭发现',
    'enableDiscoveryHint': '点击右上角 WiFi 图标开启发现',
    'lastStartFailed': '上次启动失败:{error}',
    'searchingDevices': '正在搜索局域网设备...',
    'noChatHistory': '暂无聊天记录',
    'waitingForPeer': '等待对方连接中...',
    'timeJustNow': '刚刚',
    'timeMinutesAgo': '{minutes}分钟前',
    // QR Tool
    'qrTool': '二维码',
    'qrGenerate': '生成',
    'qrRecognize': '识别',
    'qrContent': '内容',
    'qrContentHint': '输入文本、网址、WiFi 配置等',
    'qrSave': '保存图片',
    'qrShare': '分享图片',
    'qrBasicSettings': '基础设置',
    'qrErrorLevel': '容错级别',
    'qrErrorLevelLow': 'L (7%)',
    'qrErrorLevelMedium': 'M (15%)',
    'qrErrorLevelQuartile': 'Q (25%)',
    'qrErrorLevelHigh': 'H (30%)',
    'qrForeground': '前景色',
    'qrBackground': '背景色',
    'qrAdvancedSettings': '高级设置',
    'qrShape': '形状',
    'qrShapeSquares': '方块',
    'qrShapeSmooth': '圆滑',
    'qrShapeDots': '圆点',
    'qrShapeRounded': '圆角',
    'qrGradient': '渐变填充',
    'qrCustomColor': '自定义颜色',
    'qrCustomColorDesc': '选择 RGB 颜色值,例如 255,0,0',
    'qrCustomColorTitle': 'RGB 颜色选择器',
    'qrQuietZone': '静区宽度',
    'qrDensity': '密度',
    'qrRounding': '圆角程度',
    'qrLogo': '嵌入 Logo',
    'qrNoLogo': '未设置',
    'qrLogoSet': '已设置',
    'qrLogoErrorLevelHint': 'Logo 会覆盖数据模块,纠错级别已自动提升至 Q (25%)',
    'qrPickLogo': '选择 Logo 图片',
    'qrRemoveLogo': '移除 Logo',
    'qrSavedToGallery': '已保存到相册',
    'qrSaveSuccess': '图片已保存到:',
    'qrSaveFailed': '保存失败',
    'qrShareFailed': '分享失败',
    'qrPickImage': '点击选择图片,或将图片拖拽到此处',
    'qrDragHint': '支持包含二维码的 PNG / JPG 图片',
    'qrNoResult': '未识别到二维码',
    'qrDecodeResult': '识别结果:',
    'qrDecodeTime': '识别时间:',
    'qrDecodeFailed': '识别失败',
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
