import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

class SftpTab {
  final SftpProvider provider;
  final TextEditingController searchController;
  bool isDragOver = false;
  bool showRawValues = true;
  SortField sortField = SortField.name;
  SortOrder sortOrder = SortOrder.asc;

  SftpTab({required this.provider, required this.searchController});
}

class _SftpScreenState extends State<SftpScreen> {
  // ---- 多标签 / 网格布局 ----
  final List<SftpTab> _tabs = [];
  int _activeTabIndex = 0;
  bool _isGridLayout = false;

  // ---- 跨 Tab 共享的远端剪贴板(支持不同窗口间复制/粘贴) ----
  final List<String> _clipboardPaths = [];
  bool _clipboardIsCut = false;

  SftpTab get _activeTab => _tabs[_activeTabIndex];

  @override
  void initState() {
    super.initState();
    // 首个 tab 必须同步创建:首次 build 就会读 _activeTab,
    // 若延迟到 post-frame,_tabs 为空会 RangeError
    _initFirstTab();
  }

  void _initFirstTab() {
    final provider = SftpProvider();
    _attachTab(provider);
    _attachToSshAndList(provider);
  }

  void _attachTab(SftpProvider provider) {
    _tabs.add(SftpTab(
      provider: provider,
      searchController: TextEditingController(),
    ));
    // 屏幕直接持有 provider 实例(不经 Provider 包裹), provider 内部
    // isLoading/_files 等变化不会自动让 widget 重绘, 需手动桥接。
    // 用命名函数做 listener, 关闭 tab 时才能精确 removeListener。
    provider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 关闭 tab 时先摘 listener 再 dispose, 否则 ChangeNotifier.dispose
  /// 在 debug 下因仍有活跃 listener 触发断言, 异常中断后续逻辑。
  void _disposeTab(SftpTab tab) {
    tab.provider.removeListener(_onProviderChanged);
    tab.provider.dispose();
    tab.searchController.dispose();
  }

  void _attachToSshAndList(SftpProvider provider) {
    final loc = AppLocalizations.of(context);
    // 首个 tab 的 attach 在 initState 里跑时 context 尚未 attach 到 widget tree,
    // 不能同步读 SshProvider —— 放到 post-frame, 此时 context 已可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sshProvider = context.read<SshProvider>();
      provider.markLoading();
      provider
          .attachToSsh(sshProvider.sshService)
          .then((_) => provider.listDirectory('/'))
          .catchError((Object e) {
        // attach 或首次 list 失败:把 error 记到 provider,界面显示错误+重试
        provider.reportError(e.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.sftpErrorWithDetail('$e'))),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      _disposeTab(tab);
    }
    super.dispose();
  }

  // ---- Tab 增删与切换 ----

  void _addTab() {
    final provider = SftpProvider();
    _attachTab(provider);
    _attachToSshAndList(provider);
    setState(() => _activeTabIndex = _tabs.length - 1);
  }

  void _closeOtherTabs(int keepIndex) {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (i != keepIndex) _closeTab(i);
    }
  }

  void _closeAllTabs() {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      _closeTab(i);
    }
  }

  void _closeTab(int index) {
    if (!_tabs[index].provider.hasLoadStarted) return; // 未加载完成的 tab 直接移除
    final tab = _tabs[index];
    _disposeTab(tab);
    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (_activeTabIndex == index) {
      _activeTabIndex = index < _tabs.length ? index : 0;
    }
    setState(() {});
  }

  void _switchTab(int index) {
    setState(() => _activeTabIndex = index);
  }

  List<SftpFileItem> _getFilteredFiles(SftpTab tab) {
    final query = tab.searchController.text.toLowerCase();
    final list = query.isEmpty
        ? List<SftpFileItem>.from(tab.provider.files)
        : tab.provider.files.where((file) {
              return file.name.toLowerCase().contains(query);
            }).toList();
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      int cmp;
      switch (tab.sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortField.size:
          cmp = a.size.compareTo(b.size);
        case SortField.modified:
          cmp = a.modifiedAt.compareTo(b.modifiedAt);
      }
      return tab.sortOrder == SortOrder.asc ? cmp : -cmp;
    });
    return list;
  }

  /// 手动刷新当前目录:成功后显示提示,失败显示错误详情。
  Future<void> _refreshTab(BuildContext context, SftpTab tab) async {
    final loc = AppLocalizations.of(context);
    final ok = await tab.provider.refreshDirectory();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.refreshed)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.errorWithDetail(tab.provider.error ?? ''))),
      );
    }
  }

  /// 顶部全局工具按钮:「新建 tab」和「列表/网格布局切换」直接显示, 不走弹框
  List<Widget> _buildGlobalToolbarButtons(AppLocalizations loc, SftpTab tab, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return [
      IconButton(
        icon: const Icon(Icons.add, size: 18),
        tooltip: loc.newSftpTab,
        onPressed: _addTab,
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
      IconButton(
        icon: Icon(
          _isGridLayout ? Icons.view_list : Icons.grid_on,
          size: 18,
          color: _isGridLayout ? colorScheme.primary : null,
        ),
        tooltip: _isGridLayout ? loc.tabView : loc.splitView,
        onPressed: () => setState(() => _isGridLayout = !_isGridLayout),
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
    ];
  }

  /// 面板级「更多」弹出菜单(单独文件夹窗口菜单):
  /// 粘贴 / 刷新 / 显示转换值 / 排序 / 新建文件夹 / 上传 / 在此开终端 / 前往路径
  Widget _buildPanelMoreMenu(BuildContext context, AppLocalizations loc, SftpTab tab) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
      tooltip: loc.more,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onSelected: (value) {
        switch (value) {
          case 'paste':
            _pasteFiles(context, tab: tab);
            break;
          case 'refresh':
            _refreshTab(context, tab);
            break;
          case 'show_raw':
            setState(() => tab.showRawValues = !tab.showRawValues);
            break;
          case 'sort':
            _showSortMenu(context, _tabs.indexOf(tab));
            break;
          case 'new_folder':
            _createFolder(context, tab: tab);
            break;
          case 'upload':
            _uploadFiles(context, tab: tab);
            break;
          case 'terminal':
            _openTerminalHere(context);
            break;
          case 'navigate':
            _navigateToPath(context, tab: tab);
            break;
        }
      },
      itemBuilder: (context) => [
        if (_clipboardPaths.isNotEmpty)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                Icon(_clipboardIsCut ? Icons.content_cut : Icons.copy, size: 18),
                const SizedBox(width: 8),
                Text(loc.paste),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 18),
              const SizedBox(width: 8),
              Text(loc.refresh),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'show_raw',
          child: Row(
            children: [
              Icon(
                tab.showRawValues ? Icons.auto_awesome : Icons.code,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(tab.showRawValues ? loc.showConverted : loc.showRaw),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'sort',
          child: Row(
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 8),
              Text(loc.sort),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              const Icon(Icons.create_new_folder, size: 18),
              const SizedBox(width: 8),
              Text(loc.newFolder),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'upload',
          child: Row(
            children: [
              const Icon(Icons.upload_file, size: 18),
              const SizedBox(width: 8),
              Text(loc.upload),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'terminal',
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 18),
              const SizedBox(width: 8),
              Text(loc.openTerminalHere),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'navigate',
          child: Row(
            children: [
              const Icon(Icons.folder_special, size: 18),
              const SizedBox(width: 8),
              Text(loc.navigateToPath),
            ],
          ),
        ),
      ],
    );
  }

  void _showSortMenu(BuildContext context, int tabIndex) {
    final tab = _tabs[tabIndex];
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
            _buildSortOption(ctx, loc.sortByName, SortField.name, tab),
            _buildSortOption(ctx, loc.sortBySize, SortField.size, tab),
            _buildSortOption(ctx, loc.sortByDate, SortField.modified, tab),
            const Divider(),
            ListTile(
              leading: Icon(tab.sortOrder == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward),
              title: Text(tab.sortOrder == SortOrder.asc ? loc.ascending : loc.descending),
              onTap: () {
                setState(() {
                  tab.sortOrder = tab.sortOrder == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(BuildContext ctx, String label, SortField field, SftpTab tab) {
    return ListTile(
      leading: Icon(tab.sortField == field ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(label),
      onTap: () {
        setState(() => tab.sortField = field);
        Navigator.pop(ctx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final tab = _activeTab;
    final provider = tab.provider;
    final theme = Theme.of(context);
    final conn = context.read<SshProvider>().currentConnection;

    // 标题栏/工具栏按钮区:桌面端固定尺寸,移动端用默认
    final btnStyle = const BoxConstraints(minWidth: 36, minHeight: 36);

    return Scaffold(
      appBar: CustomTitleBar.isDesktop ? null : AppBar(
        title: Text('${conn?.name ?? "SSH"} - ${loc.sftp}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (provider.canGoBack) {
              provider.goBack();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        actions: [
          if (provider.isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: loc.selectAll,
              onPressed: provider.selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: loc.deselectAll,
              onPressed: provider.clearSelection,
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
            if (!_isGridLayout && _clipboardPaths.isNotEmpty)
              IconButton(
                icon: Icon(_clipboardIsCut ? Icons.content_cut : Icons.copy),
                tooltip: loc.paste,
                onPressed: () => _pasteFiles(context),
              ),
            ..._buildGlobalToolbarButtons(loc, tab, btnStyle),
            if (!_isGridLayout) _buildPanelMoreMenu(context, loc, tab),
          ],
        ],
      ),
      body: Column(
        children: [
          if (CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: '${conn?.name ?? "SSH"} - ${loc.sftp}',
              showBackButton: true,
              onBack: () {
                if (provider.canGoBack) {
                  provider.goBack();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              showCloseButton: true,
              onClose: () => Navigator.of(context).maybePop(),
              actions: [
                if (provider.isSelectionMode) ...[
                  _buildTitleBarIconBtn(loc.selectAll, Icons.select_all, provider.selectAll),
                  _buildTitleBarIconBtn(loc.deselectAll, Icons.close, provider.clearSelection),
                  _buildTitleBarIconBtn(loc.delete, Icons.delete, () => _deleteSelected(context)),
                  _buildTitleBarIconBtn(loc.compress, Icons.archive, () => _compressSelected(context)),
                ] else ...[
                  if (!_isGridLayout && _clipboardPaths.isNotEmpty)
                    _buildTitleBarIconBtn(
                      loc.paste,
                      _clipboardIsCut ? Icons.content_cut : Icons.copy,
                      () => _pasteFiles(context),
                    ),
                  ..._buildGlobalToolbarButtons(loc, tab, btnStyle),
                  if (!_isGridLayout) _buildPanelMoreMenu(context, loc, tab),
                ],
              ],
            ),
          if (!_isGridLayout)
            _buildTabBar(theme),
          Expanded(
            child: _isGridLayout
                ? _buildGridBody(theme)
                : _buildActiveTabBody(context, tab),
          ),
        ],
      ),
    );
  }

  /// 标签页条:每个 tab 一个可点击 tab,显示各自远端路径,支持关闭/右键菜单
  Widget _buildTabBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      height: 36,
      color: theme.colorScheme.surface,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = index == _activeTabIndex;
                return GestureDetector(
                  key: ValueKey('sftp_tab_$index'),
                  onTap: () => _switchTab(index),
                  onSecondaryTapUp: (details) =>
                      _showSftpTabContextMenu(context, details.globalPosition, index),
                  onTertiaryTapUp: (details) => _closeTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive ? colorScheme.primaryContainer : Colors.transparent,
                      border: Border(
                        right: BorderSide(color: theme.dividerColor, width: 0.5),
                        bottom: BorderSide(
                          color: isActive ? colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 独立返回上一级(每个 tab 各一份; 根目录时隐藏)
                        if (tab.provider.canGoBack)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: GestureDetector(
                              onTap: () => tab.provider.goBack(),
                              child: Icon(
                                Icons.arrow_back,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Icon(
                          Icons.folder,
                          size: 15,
                          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tab.provider.currentPath,
                            style: TextStyle(
                              fontSize: 13,
                              color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_tabs.length > 1)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: GestureDetector(
                              onTap: () => _closeTab(index),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// tab 右键菜单:新建 / 关闭 / 关闭其它 / 关闭全部
  void _showSftpTabContextMenu(BuildContext context, Offset position, int index) {
    final loc = AppLocalizations.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx.clamp(0, MediaQuery.of(context).size.width),
        position.dy.clamp(0, MediaQuery.of(context).size.height),
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'new',
          child: Row(
            children: [
              const Icon(Icons.add, size: 18),
              const SizedBox(width: 8),
              Text(loc.newSftpTab),
            ],
          ),
        ),
        if (_tabs.length > 1) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'close',
            child: Row(
              children: [
                const Icon(Icons.close, size: 18),
                const SizedBox(width: 8),
                Text(loc.closeTab),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'close_others',
            child: Row(
              children: [
                const Icon(Icons.close_fullscreen, size: 18),
                const SizedBox(width: 8),
                Text(loc.closeOtherTabs),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'close_all',
            child: Row(
              children: [
                const Icon(Icons.close_fullscreen, size: 18),
                const SizedBox(width: 8),
                Text(loc.closeAllTabs),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'new':
          _addTab();
          break;
        case 'close':
          _closeTab(index);
          break;
        case 'close_others':
          _closeOtherTabs(index);
          break;
        case 'close_all':
          _closeAllTabs();
          break;
      }
    });
  }

  /// 标签页模式:只渲染激活 tab(面板级菜单已在顶部工具栏右侧)
  Widget _buildActiveTabBody(BuildContext context, SftpTab tab) {
    final theme = Theme.of(context);
    // 外层 Expanded 给 Stack 有限高度; _buildTabContent 现在是单层 Column
    // (主大小 max), 直接作为 Stack 子项即可填满, 无嵌套 flex 冲突。
    final body = Stack(
      children: [
        _buildTabContent(context, tab),
        if (tab.isDragOver)
          Positioned.fill(child: _buildDragOverlay(context, theme)),
      ],
    );
    return DropTarget(
      onDragEntered: (_) => setState(() => tab.isDragOver = true),
      onDragExited: (_) => setState(() => tab.isDragOver = false),
      onDragDone: (details) async {
        setState(() => tab.isDragOver = false);
        await _handleDroppedFiles(details.files, tab: tab);
      },
      child: body,
    );
  }

  /// 网格模式:所有 tab 以 2xN 网格同时显示,每个面板独立渲染
  /// 面板级「更多」菜单放在每个面板标题栏(右侧关闭按钮左侧), 不单独占一行
  ///
  /// 用 Column/Row/Expanded 手动布局, 不用 GridView(SliverGrid),
  /// 避免 SliverGridDelegateWithFixedCrossAxisCount 在 0/Infinity 高度下
  /// 构造非法 TransformLayer 导致整片空白。
  Widget _buildGridBody(ThemeData theme) {
    if (_tabs.isEmpty) {
      return const Center(child: Text('No tabs open'));
    }
    const perRow = 2;
    final rowCount = (_tabs.length + perRow - 1) ~/ perRow;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 防御:高度为 0/NaN/Infinity 时(窗口刚 resize、父级尚未布局完),
        // 不能把面板塞进 unbounded 的 ListView(item 内的 Expanded 会
        // 解算出 NaN), 也不应再按 0 高度均分。此时只给一个可见的提示,
        // 等父级恢复合法高度后下一帧自然走网格分支。
        final maxHeight = constraints.maxHeight;
        if (maxHeight.isNaN || maxHeight.isInfinite || maxHeight <= 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('窗口尺寸过小，请拉大窗口以显示文件网格'),
            ),
          );
        }
        return Column(
          children: [
            for (int r = 0; r < rowCount; r++)
              Expanded(
                child: Row(
                  children: [
                    for (int c = 0; c < perRow; c++)
                      Expanded(
                        child: (r * perRow + c) < _tabs.length
                            ? Padding(
                                padding: EdgeInsets.only(
                                  right: c < perRow - 1 ? 1 : 0,
                                  bottom: r < rowCount - 1 ? 1 : 0,
                                ),
                                child: _buildGridPanel(
                                    context, r * perRow + c),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// 网格面板:每个 tab 一个独立面板(拖放 + 面板标题栏 + 内容)
  Widget _buildGridPanel(BuildContext context, int index) {
    final tab = _tabs[index];
    final isActive = index == _activeTabIndex;
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => tab.isDragOver = true),
      onDragExited: (_) => setState(() => tab.isDragOver = false),
      onDragDone: (details) async {
        setState(() {
          tab.isDragOver = false;
          _activeTabIndex = index;
        });
        await _handleDroppedFiles(details.files, tab: tab);
      },
      child: Container(
        color: theme.colorScheme.surface,
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? theme.colorScheme.primary : theme.dividerColor,
            width: isActive ? 1 : 0.5,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  // 左上角: 返回上一级(独立, 每个面板各一份; 根目录时禁用但保留可视占位)
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: tab.provider.canGoBack
                          ? null
                          : theme.colorScheme.onSurfaceVariant.withAlpha(80),
                    ),
                    tooltip: 'Back',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: tab.provider.canGoBack ? () => tab.provider.goBack() : null,
                  ),
                  Icon(
                    Icons.folder,
                    size: 14,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab.provider.currentPath,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 面板级「更多」菜单: 放在关闭按钮左侧(不单独占一行)
                  _buildPanelMoreMenu(context, AppLocalizations.of(context), tab),
                  if (_tabs.length > 1)
                    IconButton(
                      icon: Icon(Icons.close, size: 16),
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _closeTab(index),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildTabContent(context, tab)),
          ],
        ),
      ),
    );
  }

  /// 单个 tab 的文件区:搜索框 + 文件列表
  ///
  /// 只用一层 Column:搜索框(固定高) + 文件区(Expanded)。
  /// 不能"Column 里再套 Column, 内层放 Expanded"——外层 Column 作为
  /// Stack 的 loose 子项会按内容收缩, 内层 Expanded 的 flex 空间随之
  /// 解算出 0/NaN → 引擎 "TransformLayer invalid matrix" → 列表区塌陷为空白。
  Widget _buildTabContent(BuildContext context, SftpTab tab) {
    final loc = AppLocalizations.of(context);
    final provider = tab.provider;
    final filteredFiles = _getFilteredFiles(tab);
    // 文件区:空白处右键弹「粘贴」菜单
    final fileArea = Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) =>
            _showBlankAreaContextMenu(context, details.globalPosition, tab),
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(provider.error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => provider.refreshDirectory(),
                          child: Text(loc.retry),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => provider.refreshDirectory(),
                    child: filteredFiles.isEmpty
                        ? Center(
                            child: Text(
                              tab.searchController.text.trim().isEmpty
                                  ? loc.folderEmpty
                                  : loc.noMatchingFiles,
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredFiles.length,
                            itemBuilder: (ctx, i) {
                              final file = filteredFiles[i];
                              try {
                                final tile = FileListTile(
                                  file: file,
                                  isSelected:
                                      provider.selectedFiles.contains(file.path),
                                  showRawValues: tab.showRawValues,
                                  onTap: () {
                                    if (provider.isSelectionMode) {
                                      provider.toggleSelection(file.path);
                                    } else if (file.isDirectory) {
                                      // 目录:单击直接进入;多选时单击选中
                                      provider.clearSelection();
                                      provider.navigateTo(file.path);
                                    } else {
                                      _editFile(context, file.path);
                                    }
                                  },
                                  onDoubleTap: () {
                                    if (file.isDirectory &&
                                        provider.isSelectionMode) {
                                      // 多选模式下单击只选中,双击仍兜底进入
                                      provider.clearSelection();
                                      provider.navigateTo(file.path);
                                    }
                                  },
                                  onLongPress: () {
                                    provider.toggleSelection(file.path);
                                  },
                                  // PC: 右键文件/目录 弹出与 ⋮ 一致的菜单
                                  onRightClick: (position) => _showFileContextMenu(
                                      context, position, file),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (value) => _handleMenuAction(
                                        context, value, file),
                                    itemBuilder: (ctx) =>
                                        _buildFileMenuItems(loc, file),
                                  ),
                                );
                                return tile;
                              } catch (e, st) {
                                debugPrint(
                                    '[SFTP] 行 $i (${file.name}) build 失败: $e\n$st');
                                return Container(
                                  height: 40,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Text(
                                      '[BUILD ERROR] ${file.name}: $e',
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 11)),
                                );
                              }
                            },
                          ),
                  ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: tab.searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: loc.searchFiles,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        fileArea,
      ],
    );
  }

  Widget _buildDragOverlay(BuildContext context, ThemeData theme) {
    final loc = AppLocalizations.of(context);
    return Container(
      color: theme.colorScheme.primary.withAlpha(30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(loc.dragFilesOrFoldersHere,
                style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }

  /// 文件行「显示菜单」(右侧 ⋮)的菜单项列表: 供 ⋮ 按钮和 PC 右键复用
  List<PopupMenuEntry<String>> _buildFileMenuItems(AppLocalizations loc, SftpFileItem file) {
    return [
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
            const Icon(Icons.delete, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            Text(loc.delete, style: const TextStyle(color: Colors.red)),
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
    ];
  }

  /// PC: 右键文件/目录 弹出与右侧 ⋮「显示菜单」完全一致的菜单
  void _showFileContextMenu(BuildContext context, Offset position, SftpFileItem file) {
    final loc = AppLocalizations.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx.clamp(0, MediaQuery.of(context).size.width),
        position.dy.clamp(0, MediaQuery.of(context).size.height),
        position.dx + 1,
        position.dy + 1,
      ),
      items: _buildFileMenuItems(loc, file),
    ).then((value) {
      if (value != null) _handleMenuAction(context, value, file);
    });
  }

  /// PC: 右键文件区空白处, 弹出「粘贴」菜单(有剪贴板时), 可粘贴到当前目录
  void _showBlankAreaContextMenu(BuildContext context, Offset position, SftpTab tab) {
    final loc = AppLocalizations.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx.clamp(0, MediaQuery.of(context).size.width),
        position.dy.clamp(0, MediaQuery.of(context).size.height),
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'paste',
          enabled: _clipboardPaths.isNotEmpty,
          child: Row(
            children: [
              Icon(_clipboardIsCut ? Icons.content_cut : Icons.copy, size: 18),
              const SizedBox(width: 8),
              Text(loc.paste),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'paste' && _clipboardPaths.isNotEmpty) {
        _pasteFiles(context, tab: tab);
      }
    });
  }

  void _handleMenuAction(BuildContext context, String action, SftpFileItem file) {
    final loc = AppLocalizations.of(context);
    switch (action) {
      case 'view':
        _editFile(context, file.path, tab: _activeTab);
        break;
      case 'edit':
        _editFile(context, file.path, tab: _activeTab);
        break;
      case 'terminal':
        _openTerminalHere(context);
        break;
      case 'download':
        _downloadFile(context, file.path, tab: _activeTab);
        break;
      case 'delete':
        _deleteFile(context, file.path);
        break;
      case 'rename':
        _renameFile(context, file, tab: _activeTab);
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

  void _renameFile(BuildContext context, SftpFileItem file, {SftpTab? tab}) {
    final loc = AppLocalizations.of(context);
    final sftpProvider = (tab ?? _activeTab).provider;
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
              SnackBar(content: Text(loc.errorWithDetail('$e'))),
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

  void _pasteFiles(BuildContext context, {SftpTab? tab}) async {
    final loc = AppLocalizations.of(context);
    final activeTab = tab ?? _activeTab;
    final sftpProvider = activeTab.provider;
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
            SnackBar(content: Text(loc.errorWithDetail('$e'))),
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

  void _navigateToPath(BuildContext context, {SftpTab? tab}) {
    final loc = AppLocalizations.of(context);
    final sftpProvider = (tab ?? _activeTab).provider;
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
                sftpProvider.navigateTo(path);
              }
            },
            child: Text(loc.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _editFile(BuildContext context, String remotePath, {SftpTab? tab}) async {
    final sftpProvider = (tab ?? _activeTab).provider;
    final loc = AppLocalizations.of(context);

    try {
      // Try to read with 5MB limit
      final content = await sftpProvider.sftpService.readFileContent(remotePath);
      if (content != null) {
        // File is within size limit, open editor
        _openEditor(context, remotePath, content, loc, tab: tab);
        return;
      }

      // File is too large, try to read for preview only
      final size = await sftpProvider.sftpService.getFileSize(remotePath);
      if (size > 5 * 1024 * 1024) {
        // Show read-only preview for large files
        if (mounted) {
          _showLargeFilePreview(context, remotePath, size, loc, tab: tab);
        }
        return;
      }

      // Other error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.cannotReadFile)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.errorWithDetail('$e'))),
        );
      }
    }
  }

  void _openEditor(BuildContext context, String remotePath, String content, AppLocalizations loc, {SftpTab? tab}) {
    final sftpProvider = (tab ?? _activeTab).provider;
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
        await sftpProvider.sftpService.writeFileContent(remotePath, result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.fileSaved(p.basename(remotePath)))),
          );
        }
      }
    });
  }

  void _showLargeFilePreview(BuildContext context, String remotePath, int fileSize, AppLocalizations loc, {SftpTab? tab}) {
    final sftpProvider = (tab ?? _activeTab).provider;

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
                        loc.readOnlyPreview(_formatFileSize(fileSize)),
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
                      return Center(child: Text(loc.failedToLoadFile));
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

  Future<void> _handleDroppedFiles(List<DropItem> droppedFiles, {SftpTab? tab}) async {
    final sftpProvider = (tab ?? _activeTab).provider;

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

    final filteredItems = await _checkConflictsAndFilter(items, tab: tab);
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

  Future<List<BatchUploadItem>?> _checkConflictsAndFilter(List<BatchUploadItem> items, {SftpTab? tab}) async {
    final sftpProvider = (tab ?? _activeTab).provider;
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

  Future<void> _uploadFiles(BuildContext context, {SftpTab? tab}) async {
    final sftpProvider = (tab ?? _activeTab).provider;
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

    final filteredItems = await _checkConflictsAndFilter(items, tab: tab);
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

  Future<void> _downloadFile(BuildContext context, String remotePath, {SftpTab? tab}) async {
    final sftpProvider = (tab ?? _activeTab).provider;
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

  Future<void> _deleteFile(BuildContext context, String path, {SftpTab? tab}) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = (tab ?? _activeTab).provider;
    final name = p.basename(path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text(loc.deleteFolderConfirm(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
        ],
      ),
    );
    if (confirmed == true) {
      await sftpProvider.remove(path);
      await sftpProvider.listDirectory();
    }
  }

  void _deleteSelected(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = _activeTab.provider;
    final count = sftpProvider.selectedFiles.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text(loc.deleteFilesConfirm(count)),
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

  void _createFolder(BuildContext context, {SftpTab? tab}) async {
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
      final provider = (tab ?? _activeTab).provider;
      try {
        await provider.createDirectory(name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.folderCreated(name))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.errorWithDetail('$e'))),
          );
        }
      }
    }
  }

  void _compressSelected(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final sftpProvider = _activeTab.provider;
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
