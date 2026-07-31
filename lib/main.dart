import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.init();
  await RssDatabaseService.init();
  await UpdateService.init();

  // Initialize desktop services
  await WindowService.init();

  runApp(const ZebraApp());
}

class ZebraApp extends StatelessWidget {
  const ZebraApp({super.key});

  @override
  Widget build(BuildContext context) {
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
