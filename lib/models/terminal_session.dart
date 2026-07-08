import 'package:xterm/xterm.dart';

class TerminalSession {
  final String id;
  final String label;
  Terminal? terminal;
  bool isLoading;
  bool isActive;

  TerminalSession({
    required this.id,
    required this.label,
    this.terminal,
    this.isLoading = true,
    this.isActive = false,
  });
}
