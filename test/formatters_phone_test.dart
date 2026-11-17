import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/utils/formatters.dart';

void main() {
  test('local Malaysian mobiles gain the +60 prefix', () {
    expect(Formatters.phone('0123456789'), '+60 12-345 6789');
    expect(Formatters.phone('011-2345 6789'), '+60 11-2345 6789');
  });

  test('numbers already carrying 60 format the same way', () {
    expect(Formatters.phone('+60 12 345 6789'), '+60 12-345 6789');
    expect(Formatters.phone('60123456789'), '+60 12-345 6789');
  });

  test('anything else is shown as typed', () {
    expect(Formatters.phone('12345'), '12345');
    expect(Formatters.phone('+44 20 7946 0958'), '+44 20 7946 0958');
  });

  test('dates always print in the device time zone', () {
    final utc = DateTime.utc(2026, 11, 16, 16, 50);
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    expect(Formatters.shortDateTime(utc), endsWith('$hh:$mm'));
    expect(Formatters.shortDateTime(utc), Formatters.shortDateTime(local));
  });

  test('both dashboards greet with the same rule', () {
    expect(Formatters.greeting(DateTime(2026, 1, 1, 1, 20)), 'Good Evening');
    expect(Formatters.greeting(DateTime(2026, 1, 1, 9)), 'Good Morning');
    expect(Formatters.greeting(DateTime(2026, 1, 1, 13)), 'Good Afternoon');
    expect(Formatters.greeting(DateTime(2026, 1, 1, 19)), 'Good Evening');
  });
}
