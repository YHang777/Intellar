import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextSizeOption {
  standard(1.0, 'Default'),
  large(1.15, 'Large'),
  extraLarge(1.3, 'Larger');

  const TextSizeOption(this.scale, this.label);
  final double scale;
  final String label;
}

class AccessibilitySettings {
  const AccessibilitySettings({
    this.textSize = TextSizeOption.standard,
    this.highContrast = false,
    this.boldText = false,
  });

  final TextSizeOption textSize;
  final bool highContrast;
  final bool boldText;

  AccessibilitySettings copyWith({
    TextSizeOption? textSize,
    bool? highContrast,
    bool? boldText,
  }) =>
      AccessibilitySettings(
        textSize: textSize ?? this.textSize,
        highContrast: highContrast ?? this.highContrast,
        boldText: boldText ?? this.boldText,
      );
}

class AccessibilitySettingsNotifier
    extends StateNotifier<AccessibilitySettings> {
  AccessibilitySettingsNotifier({bool load = true})
      : super(const AccessibilitySettings()) {
    if (load) _load();
  }

  static const _textKey = 'a11y_text_size';
  static const _contrastKey = 'a11y_high_contrast';
  static const _boldKey = 'a11y_bold_text';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_textKey);
      if (!mounted || _changed) return;
      state = AccessibilitySettings(
        textSize: TextSizeOption.values.firstWhere(
          (o) => o.name == name,
          orElse: () => TextSizeOption.standard,
        ),
        highContrast: prefs.getBool(_contrastKey) ?? false,
        boldText: prefs.getBool(_boldKey) ?? false,
      );
    } catch (_) {}
  }

  bool _changed = false;

  Future<void> patch(
          AccessibilitySettings Function(AccessibilitySettings current) change) =>
      update(change(state));

  Future<void> update(AccessibilitySettings next) async {
    _changed = true;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_textKey, next.textSize.name);
      await prefs.setBool(_contrastKey, next.highContrast);
      await prefs.setBool(_boldKey, next.boldText);
    } catch (_) {}
  }
}

final accessibilitySettingsProvider = StateNotifierProvider<
    AccessibilitySettingsNotifier, AccessibilitySettings>(
  (ref) => AccessibilitySettingsNotifier(),
);
