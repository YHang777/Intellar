import 'package:flutter/services.dart';

class AppFormatters {
  static final List<TextInputFormatter> phone = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
    LengthLimitingTextInputFormatter(20),
  ];

  static List<TextInputFormatter> wholeNumber(int maxDigits) => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxDigits),
      ];

  static final List<TextInputFormatter> money = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
    LengthLimitingTextInputFormatter(13),
  ];

  static final List<TextInputFormatter> centimetres = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d?)?')),
  ];
}
