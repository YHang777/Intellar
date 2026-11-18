// A store's weekly opening schedule. One entry per weekday (1 = Monday …
// 7 = Sunday, as DateTime.weekday); a missing day is closed. Times are
// minutes after midnight, same-day only (closing must be after opening).
class DayHours {
  const DayHours(this.openMinutes, this.closeMinutes);

  final int openMinutes;
  final int closeMinutes;

  bool get isValid =>
      openMinutes >= 0 &&
      closeMinutes <= 24 * 60 &&
      closeMinutes > openMinutes;

  @override
  bool operator ==(Object other) =>
      other is DayHours &&
      other.openMinutes == openMinutes &&
      other.closeMinutes == closeMinutes;

  @override
  int get hashCode => Object.hash(openMinutes, closeMinutes);
}

class WeeklyHours {
  const WeeklyHours(this.days);

  final Map<int, DayHours> days;

  static const dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // The stores and their buyers are in Malaysia (UTC+8, no daylight saving),
  // so "open now" is judged on Malaysian time whatever the phone's zone.
  static DateTime malaysiaNow([DateTime? nowUtc]) =>
      (nowUtc ?? DateTime.now()).toUtc().add(const Duration(hours: 8));

  static const WeeklyHours typical = WeeklyHours({
    1: DayHours(9 * 60, 18 * 60),
    2: DayHours(9 * 60, 18 * 60),
    3: DayHours(9 * 60, 18 * 60),
    4: DayHours(9 * 60, 18 * 60),
    5: DayHours(9 * 60, 18 * 60),
    6: DayHours(10 * 60, 14 * 60),
  });

  bool get isEmpty => days.isEmpty;

  /// The first problem a seller must fix, or null when every day is valid.
  String? get problem {
    for (var d = 1; d <= 7; d++) {
      final h = days[d];
      if (h != null && !h.isValid) {
        return '${dayShort[d - 1]}: closing time must be after opening time';
      }
    }
    return null;
  }

  WeeklyHours withDay(int weekday, DayHours? hours) {
    final next = Map<int, DayHours>.of(days);
    if (hours == null) {
      next.remove(weekday);
    } else {
      next[weekday] = hours;
    }
    return WeeklyHours(next);
  }

  // ── Firestore shape: {"mon": {"open": "09:00", "close": "18:00"}, …} ──

  static WeeklyHours? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final days = <int, DayHours>{};
    for (var i = 0; i < dayKeys.length; i++) {
      final entry = raw[dayKeys[i]];
      if (entry is! Map) continue;
      final open = _parse(entry['open']);
      final close = _parse(entry['close']);
      if (open == null || close == null) continue;
      final h = DayHours(open, close);
      if (h.isValid) days[i + 1] = h;
    }
    return days.isEmpty ? null : WeeklyHours(days);
  }

  Map<String, Object> toMap() => {
        for (final e in days.entries)
          dayKeys[e.key - 1]: {
            'open': _hhmm(e.value.openMinutes),
            'close': _hhmm(e.value.closeMinutes),
          },
      };

  static int? _parse(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 24 || min > 59 || (h == 24 && min > 0)) return null;
    return h * 60 + min;
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  // ── What buyers read ──

  /// "9:00 am", "12:30 pm", "12:00 am" for midnight.
  static String formatTime(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final suffix = h24 < 12 ? 'am' : 'pm';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $suffix';
  }

  // Non-breaking space inside each time, so a wrapping line never splits
  // "2:00" from "pm".
  static String _t(int minutes) => formatTime(minutes).replaceAll(' ', ' ');

  static String _range(DayHours h) =>
      '${_t(h.openMinutes)} – ${_t(h.closeMinutes)}';

  /// Consecutive days with the same hours are grouped:
  /// "Mon–Fri 9:00 am – 6:00 pm · Sat 10:00 am – 2:00 pm · Sun closed".
  String get summary {
    final parts = <String>[];
    var d = 1;
    while (d <= 7) {
      final h = days[d];
      var end = d;
      while (end < 7 && days[end + 1] == h) {
        end++;
      }
      final label = end == d
          ? dayShort[d - 1]
          : '${dayShort[d - 1]}–${dayShort[end - 1]}';
      parts.add(h == null ? '$label closed' : '$label ${_range(h)}');
      d = end + 1;
    }
    return parts.join(' · ');
  }

  bool isOpenAt(DateTime malaysiaTime) {
    final h = days[malaysiaTime.weekday];
    if (h == null) return false;
    final m = malaysiaTime.hour * 60 + malaysiaTime.minute;
    return m >= h.openMinutes && m < h.closeMinutes;
  }

  /// "Open now · closes 6:00 pm" or "Closed · opens Sat 10:00 am".
  String statusAt(DateTime malaysiaTime) {
    final today = days[malaysiaTime.weekday];
    final m = malaysiaTime.hour * 60 + malaysiaTime.minute;
    if (today != null && m >= today.openMinutes && m < today.closeMinutes) {
      return 'Open now · closes ${_t(today.closeMinutes)}';
    }
    if (today != null && m < today.openMinutes) {
      return 'Closed · opens today ${_t(today.openMinutes)}';
    }
    for (var step = 1; step <= 7; step++) {
      final wd = (malaysiaTime.weekday - 1 + step) % 7 + 1;
      final h = days[wd];
      if (h == null) continue;
      final when = step == 1 ? 'tomorrow' : dayShort[wd - 1];
      return 'Closed · opens $when ${_t(h.openMinutes)}';
    }
    return 'Closed';
  }
}
