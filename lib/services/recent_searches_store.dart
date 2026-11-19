import 'package:shared_preferences/shared_preferences.dart';

// Recent searches are per account, like chat history.
class RecentSearchesStore {
  RecentSearchesStore({this.ownerId});

  final String? ownerId;

  static const String prefsKey = 'marketplace_recent_searches';
  static const int maxEntries = 10;

  String get _key => '${prefsKey}_$ownerId';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(prefsKey)) await prefs.remove(prefsKey);
    if (ownerId == null) return const [];
    return prefs.getStringList(_key) ?? const [];
  }

  Future<void> save(List<String> terms) async {
    if (ownerId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, terms.take(maxEntries).toList());
  }
}
