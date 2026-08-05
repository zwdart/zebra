import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'database/database_service.dart';
import 'l10n/app_localizations.dart';
import 'providers/connection_provider.dart';
import 'providers/ssh_provider.dart';
import 'providers/sftp_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/shell_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/sftp_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/process_screen.dart';
import 'screens/cleanup_screen.dart';
import 'providers/monitor_provider.dart';
import 'providers/process_provider.dart';
import 'providers/cleanup_provider.dart';
import 'providers/update_provider.dart';
import 'providers/rss_provider.dart';
import 'providers/about_provider.dart';
import 'providers/blog_provider.dart';
import 'providers/discovery_provider.dart';
import 'providers/feedback_provider.dart';
import 'providers/diary_provider.dart';
import 'database/rss_database_service.dart';
import 'services/update_service.dart';
import 'services/window_service.dart';
import 'features/lan_chat/providers/lan_discovery_provider.dart';
import 'features/lan_chat/providers/chat_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.init();
  await RssDatabaseService.init();
  await UpdateService.init();

  // Initialize desktop services
  await WindowService.init();

  final userName = await _defaultUserName();
  // 设备 ID 首次生成后持久化,重启不变,避免同一设备在对方设备列表中被当成新设备重复显示
  final prefs = await SharedPreferences.getInstance();
  final lanDeviceId = prefs.getString(_lanDeviceIdPrefKey) ??
      const Uuid().v4().toString();
  await prefs.setString(_lanDeviceIdPrefKey, lanDeviceId);

  runApp(ZebraApp(defaultUserName: userName, lanDeviceId: lanDeviceId));
}

const _userNamePrefKey = 'lan_chat_user_name';
const _lanDeviceIdPrefKey = 'lan_chat_device_id';

/// 默认用户名：系统主机名 → 设备型号 → 持久化随机字符串
Future<String> _defaultUserName() async {
  // 1. 优先取已持久化的用户名
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_userNamePrefKey);
  if (saved != null && saved.isNotEmpty) return saved;

  // 2. 系统主机名
  try {
    final hostname = Platform.localHostname;
    if (hostname.isNotEmpty && hostname != 'localhost') {
      final name = hostname.split('.').first;
      if (name.isNotEmpty) {
        await prefs.setString(_userNamePrefKey, name);
        return name;
      }
    }
  } catch (_) {}

  // 3. 设备型号
  try {
    final name = Platform.operatingSystemVersion.split(';').first.trim();
    if (name.isNotEmpty) {
      await prefs.setString(_userNamePrefKey, name);
      return name;
    }
  } catch (_) {}

  // 4. 随机 6 位字母数字，持久化，后续不再变
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = Random();
  final name = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  await prefs.setString(_userNamePrefKey, name);
  return name;
}

class ZebraApp extends StatelessWidget {
  final String defaultUserName;
  final String lanDeviceId;

  const ZebraApp({
    super.key,
    required this.defaultUserName,
    required this.lanDeviceId,
  });

  @override
  Widget build(BuildContext context) {
    // 发现服务与聊天服务共享同一实例，用于同步实际 TCP 监听端口
    final lanDiscovery = LanDiscoveryProvider(
        deviceId: lanDeviceId, deviceName: defaultUserName);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => SshProvider()),
        ChangeNotifierProvider(create: (_) => SftpProvider()),
        ChangeNotifierProxyProvider<SshProvider, MonitorProvider>(
          create: (_) => MonitorProvider(),
          update: (_, ssh, provider) => provider!..updateSsh(ssh),
        ),
        ChangeNotifierProxyProvider<SshProvider, ProcessProvider>(
          create: (_) => ProcessProvider(),
          update: (_, ssh, provider) => provider!..updateSsh(ssh),
        ),
        ChangeNotifierProxyProvider<SshProvider, CleanupProvider>(
          create: (_) => CleanupProvider(),
          update: (_, ssh, provider) => provider!..updateSsh(ssh),
        ),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => AboutProvider()..load()),
        ChangeNotifierProvider(create: (_) => BlogProvider()),
        ChangeNotifierProvider(create: (_) => DiscoveryProvider()),
        ChangeNotifierProvider(create: (_) => FeedbackProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()..loadEntries()),
        ChangeNotifierProvider(create: (_) => RssProvider()..init()),
        ChangeNotifierProvider(create: (_) => lanDiscovery..start()),
        ChangeNotifierProvider(create: (_) {
          final provider =
              ChatProvider(selfId: lanDeviceId, selfName: defaultUserName);
          // 服务器可能因端口占用回退到随机端口，必须同步给心跳广播
          provider.startServer().then((port) {
            if (port > 0) lanDiscovery.setTcpPort(port);
          });
          return provider;
        }),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (ctx, themeProvider, localeProvider, _) {
          return MaterialApp(
            title: 'Zebra SSH',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const ShellScreen(),
            routes: {
              '/terminal': (_) => const TerminalScreen(),
              '/sftp': (_) => const SftpScreen(),
              '/monitor': (_) => const MonitorScreen(),
              '/processes': (_) => const ProcessScreen(),
              '/cleanup': (_) => const CleanupScreen(),
            },
          );
        },
      ),
    );
  }
}
