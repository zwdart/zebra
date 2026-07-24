import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light([Color? seedColor]) {
    final color = seedColor ?? Colors.blue;
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: color,
      brightness: Brightness.light,
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData dark([Color? seedColor]) {
    final color = seedColor ?? Colors.blue;
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: color,
      brightness: Brightness.dark,
      fontFamily: 'monospace',
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static const List<(String, Color)> themeColors = [
    ('Blue', Colors.blue),
    ('Red', Colors.red),
    ('Green', Colors.green),
    ('Purple', Colors.purple),
    ('Orange', Colors.orange),
    ('Teal', Colors.teal),
    ('Pink', Colors.pink),
    ('Indigo', Colors.indigo),
    ('Brown', Colors.brown),
    ('Cyan', Colors.cyan),
  ];
}
