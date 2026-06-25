import 'package:flutter/material.dart';
import '../database/database_service.dart';
import '../models/ssh_connection.dart';

class ConnectionProvider extends ChangeNotifier {
  List<SshConnection> _connections = [];
  String _searchQuery = '';
  bool _isLoading = false;

  List<SshConnection> get connections {
    if (_searchQuery.isEmpty) return List.unmodifiable(_connections);
    final q = _searchQuery.toLowerCase();
    return _connections
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.host.toLowerCase().contains(q) ||
            c.username.toLowerCase().contains(q) ||
            (c.remark?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  List<SshConnection> get allConnections => List.unmodifiable(_connections);
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  void loadConnections() {
    _isLoading = true;
    notifyListeners();
    try {
      _connections = DatabaseService.getAllConnections();
    } catch (e) {
      debugPrint('Failed to load connections: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  SshConnection? getConnection(int id) {
    try {
      return _connections.firstWhere((c) => c.id == id);
    } catch (_) {
      return DatabaseService.getConnection(id);
    }
  }

  Future<void> addConnection(SshConnection conn) async {
    final id = DatabaseService.insertConnection(conn);
    final newConn = conn.copyWith(id: id);
    _connections.insert(0, newConn);
    notifyListeners();
  }

  Future<void> updateConnection(SshConnection conn) async {
    DatabaseService.updateConnection(conn);
    final index = _connections.indexWhere((c) => c.id == conn.id);
    if (index >= 0) {
      _connections[index] = conn;
    }
    notifyListeners();
  }

  Future<void> deleteConnection(int id) async {
    DatabaseService.deleteConnection(id);
    _connections.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}
