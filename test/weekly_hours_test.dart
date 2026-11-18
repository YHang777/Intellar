import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/store_profile.dart';
import 'package:interior_design_recommendation/models/weekly_hours.dart';

// 2026-11-16 is a Monday.
DateTime myt(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

String plain(String s) => s.replaceAll(' ', ' ');

void main() {
  const typical = WeeklyHours.typical; // Mon–Fri 9–6, Sat 10–2, Sun closed

  group('summary', () {
    test('groups consecutive days with the same hours', () {
      expect(plain(typical.summary),
          'Mon–Fri 9:00 am – 6:00 pm · Sat 10:00 am – 2:00 pm · Sun closed');
    });

    test('a midweek closed day splits the run', () {
      final h = typical.withDay(3, null);
      expect(plain(h.summary), startsWith('Mon–Tue 9:00 am – 6:00 pm · Wed closed · '
          'Thu–Fri 9:00 am – 6:00 pm'));
    });

    test('noon and midnight read naturally', () {
      expect(WeeklyHours.formatTime(12 * 60), '12:00 pm');
      expect(WeeklyHours.formatTime(0), '12:00 am');
      expect(WeeklyHours.formatTime(24 * 60), '12:00 am');
      expect(WeeklyHours.formatTime(13 * 60 + 30), '1:30 pm');
    });
  });

  group('open now', () {
    test('inside hours', () {
      expect(typical.isOpenAt(myt(16, 10)), isTrue);
      expect(plain(typical.statusAt(myt(16, 10))), 'Open now · closes 6:00 pm');
    });

    test('closing minute counts as closed', () {
      expect(typical.isOpenAt(myt(16, 18)), isFalse);
    });

    test('before opening today', () {
      expect(plain(typical.statusAt(myt(16, 8))), 'Closed · opens today 9:00 am');
    });

    test('after closing, it names tomorrow', () {
      expect(plain(typical.statusAt(myt(16, 19))), 'Closed · opens tomorrow 9:00 am');
    });

    test('Saturday evening skips the closed Sunday to Monday', () {
      expect(plain(typical.statusAt(myt(21, 15))), 'Closed · opens Mon 9:00 am');
    });

    test('Malaysian time is used whatever the phone zone', () {
      // 02:00 UTC Monday is 10:00 in Malaysia.
      final now = WeeklyHours.malaysiaNow(DateTime.utc(2026, 11, 16, 2));
      expect(now.weekday, DateTime.monday);
      expect(now.hour, 10);
      expect(typical.isOpenAt(now), isTrue);
    });
  });

  group('storage', () {
    test('round-trips the Firestore shape', () {
      final map = typical.toMap();
      expect(map['mon'], {'open': '09:00', 'close': '18:00'});
      expect(map.containsKey('sun'), isFalse, reason: 'closed days are absent');
      final back = WeeklyHours.fromMap(map)!;
      expect(back.summary, typical.summary);
    });

    test('bad entries are dropped instead of crashing', () {
      final h = WeeklyHours.fromMap({
        'mon': {'open': '09:00', 'close': '18:00'},
        'tue': {'open': '18:00', 'close': '09:00'}, // backwards
        'wed': {'open': 'nine', 'close': '18:00'},
        'thu': 'closed',
      })!;
      expect(h.days.keys, [1]);
      expect(WeeklyHours.fromMap('nonsense'), isNull);
      expect(WeeklyHours.fromMap(const {}), isNull);
    });

    test('a backwards day is reported for the seller to fix', () {
      final h = typical.withDay(2, const DayHours(18 * 60, 9 * 60));
      expect(h.problem, contains('Tue'));
      expect(typical.problem, isNull);
    });

    test('rides inside the store profile and old profiles still load', () {
      const p = StoreProfile(weeklyHours: typical, hours: 'Closed on PH');
      final back = StoreProfile.fromMap(p.toMap());
      expect(back.weeklyHours?.summary, typical.summary);
      expect(back.hours, 'Closed on PH');

      final legacy = StoreProfile.fromMap({'hours': 'Mon-Fri 9-6'});
      expect(legacy.weeklyHours, isNull);
      expect(legacy.hours, 'Mon-Fri 9-6');
      expect(const StoreProfile(weeklyHours: WeeklyHours({})).isEmpty, isTrue);
    });
  });

  group('policy quick picks', () {
    test('a tap adds the sentence, a second tap removes it', () {
      var t = '';
      t = StoreProfile.togglePhrase(t, 'Collect within 7 days');
      expect(t, 'Collect within 7 days.');
      t = StoreProfile.togglePhrase(t, 'Bring your order number');
      expect(t, 'Collect within 7 days. Bring your order number.');
      expect(StoreProfile.hasPhrase(t, 'Bring your order number'), isTrue);
      t = StoreProfile.togglePhrase(t, 'Collect within 7 days');
      expect(t, 'Bring your order number.');
    });

    test('the seller\'s own words are kept', () {
      final t = StoreProfile.togglePhrase(
          'Parking at the back', 'Call ahead before collecting');
      expect(t, 'Parking at the back. Call ahead before collecting.');
    });
  });
}
