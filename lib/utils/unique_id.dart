import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class UniqueId {
  static const _key = 'app_unique_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = _generate();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }

  static String _generate() {
    final rng = Random.secure();
    String hex(int len) {
      return List.generate(len, (_) => rng.nextInt(16).toRadixString(16)).join();
    }
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${_hexVariant(rng)}${hex(3)}-${hex(12)}';
  }

  static String _hexVariant(Random rng) {
    return (8 + rng.nextInt(4)).toRadixString(16);
  }
}
