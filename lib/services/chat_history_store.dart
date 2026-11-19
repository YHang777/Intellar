import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';

// Conversations are kept per account on the phone: a guest (or the next
// person to sign in) must never see someone else's chats.
class ChatHistoryStore {
  ChatHistoryStore({this.ownerId});

  final String? ownerId;

  static const String prefsKey = 'ai_chat_history';
  static const String activeIdKey = 'ai_chat_active_session_id';

  String get _historyKey => ownerId == null ? prefsKey : '${prefsKey}_$ownerId';
  String get _activeKey => ownerId == null ? activeIdKey : '${activeIdKey}_$ownerId';

  // Before chats were per account they shared one key; whose they were is
  // unknown, so they are removed rather than shown to anyone.
  static Future<void> _dropLegacy(SharedPreferences prefs) async {
    if (prefs.containsKey(prefsKey)) await prefs.remove(prefsKey);
    if (prefs.containsKey(activeIdKey)) await prefs.remove(activeIdKey);
  }
  static const int maxSessions = 15;
  static const int maxMessagesPerSession = 40;
  static const int maxMessageChars = 2000;

  Future<List<ChatSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (ownerId == null) return const [];
    await _dropLegacy(prefs);
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatSession.fromJson)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  Future<String?> loadActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    if (ownerId == null) return null;
    return prefs.getString(_activeKey);
  }

  Future<void> save(
    List<ChatSession> sessions, {
    String? activeSessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (ownerId == null) return;
    final capped = _cap(sessions);
    await prefs.setString(
      _historyKey,
      jsonEncode([for (final s in capped) s.toJson()]),
    );
    if (activeSessionId == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, activeSessionId);
    }
  }

  static List<ChatSession> _cap(List<ChatSession> sessions) {
    final sorted = [...sessions]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final s in sorted.take(maxSessions))
        s.copyWith(
          messages: [
            for (final m in s.messages.skip(
              s.messages.length > maxMessagesPerSession
                  ? s.messages.length - maxMessagesPerSession
                  : 0,
            ))
              m.text.length > maxMessageChars
                  ? ChatMessage(
                      role: m.role,
                      text: m.text.substring(0, maxMessageChars),
                      createdAt: m.createdAt,
                      suggestions: m.suggestions,
                    )
                  : m,
          ],
        ),
    ];
  }
}
