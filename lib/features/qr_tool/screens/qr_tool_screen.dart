import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/custom_title_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/qr_provider.dart';
import 'qr_generate_tab.dart';
import 'qr_recognize_tab.dart';

/// 二维码工具主页面:生成 / 识别 两个 Tab。
class QrToolScreen extends StatefulWidget {
  final int initialTab;

  const QrToolScreen({super.key, this.initialTab = 0});

  @override
  State<QrToolScreen> createState() => _QrToolScreenState();
}

class _QrToolScreenState extends State<QrToolScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ChangeNotifierProvider(
      create: (_) => QrProvider(),
      child: Scaffold(
        appBar: CustomTitleBar.isDesktop
            ? null
            : AppBar(
                title: Text(loc.qrTool),
                bottom: _buildTabBar(loc),
              ),
        body: Column(
          children: [
            if (CustomTitleBar.isDesktop) ...[
              CustomTitleBar(
                title: loc.qrTool,
                showBackButton: true,
              ),
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: _buildTabBar(loc),
              ),
            ],
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  QrGenerateTab(),
                  QrRecognizeTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTabBar(AppLocalizations loc) {
    return TabBar(
      controller: _tabController,
      tabs: [
        Tab(text: loc.qrGenerate),
        Tab(text: loc.qrRecognize),
      ],
    );
  }
}
