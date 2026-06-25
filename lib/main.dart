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
import 'screens/home_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/sftp_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.init();
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
            home: const HomeScreen(),
            routes: {
              '/terminal': (_) => const TerminalScreen(),
              '/sftp': (_) => const SftpScreen(),
            },
          );
        },
      ),
    );
  }
}
