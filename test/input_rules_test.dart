import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/utils/input_formatters.dart';
import 'package:interior_design_recommendation/core/utils/validators.dart';
import 'package:interior_design_recommendation/features/customer/budget/presentation/screens/budget_planner_screen.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';

String _type(List<TextInputFormatter> formatters, String text) {
  var value = TextEditingValue.empty;
  for (final ch in text.split('')) {
    final next = TextEditingValue(
      text: value.text + ch,
      selection: TextSelection.collapsed(offset: value.text.length + 1),
    );
    value = formatters.fold(next, (v, f) => f.formatEditUpdate(value, v));
  }
  return value.text;
}

void main() {
  test('a budget with cents is rounded, never inflated', () {
    expect(_type(AppFormatters.money, '1500.50'), '1500.50');
    expect(parseBudgetRm(_type(AppFormatters.money, '1500.50')), 1501);
    expect(parseBudgetRm(_type(AppFormatters.money, '1500.49')), 1500);
    expect(_type(AppFormatters.money, '-200'), '200');
    expect(parseBudgetRm(_type(AppFormatters.money, '5,000')), 5000);
    expect(_type(AppFormatters.money, 'RM 1200'), '1200');
    expect(parseBudgetRm(''), 0);
    expect(parseBudgetRm('1.2.3'), 0, reason: 'nonsense saves nothing');
  });

  test('phone fields refuse letters', () {
    expect(_type(AppFormatters.phone, '+60 12-345abc 6789'), '+60 12-345 6789');
  });

  test('furniture sizes allow one decimal place', () {
    expect(_type(AppFormatters.centimetres, '85.55'), '85.5');
    expect(_type(AppFormatters.centimetres, '12345'), '1234');
  });

  test('room sides must be 1 to 30 metres, with a clear message', () {
    expect(roomSideError('450'), isNull);
    expect(roomSideError(''), 'Enter a size');
    expect(roomSideError('50'), '100–3000 cm');
    expect(roomSideError('99999'), '100–3000 cm');
  });

  test('seller business phone must look like a phone number', () {
    String? check(String v) =>
        Validators.required(v, 'Business phone') ?? Validators.phone(v);
    expect(check(''), 'Business phone is required');
    expect(check('abc'), isNotNull);
    expect(check('+60 12-345 6789'), isNull);
  });
}
