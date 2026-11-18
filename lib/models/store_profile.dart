import 'weekly_hours.dart';

// A seller's storefront: what buyers see about how they trade (report:
// "manage their profiles and store details, including contact info, business
// hours, and branding" and "set store policies" / "accepted payment options").
// Money still moves through Stripe — these are the seller's own terms.
class StoreProfile {
  const StoreProfile({
    this.description = '',
    this.hours = '',
    this.weeklyHours,
    this.brandColorValue,
    this.logoUrl = '',
    this.pickupPolicy = '',
    this.returnPolicy = '',
    this.paymentMethods = const [],
  });

  static const List<String> paymentOptions = [
    'Card (online)',
    'Bank transfer',
    'E-wallet',
    'Cash on collection',
  ];

  // Quick picks for the policy fields; sellers can still type their own.
  // Kept short (≤ 27 characters): a chip label cannot wrap, so anything
  // longer is cut off on small phones at large text sizes.
  static const List<String> pickupPresets = [
    'Collect within 3 days',
    'Collect within 7 days',
    'Bring your order number',
    'Call before collecting',
    'Loading help available',
  ];

  static const List<String> returnPresets = [
    '7-day returns, unused items',
    '14-day returns with receipt',
    'Exchange only, no refunds',
    'Damaged items replaced',
    'No returns on custom orders',
  ];

  /// Adds [phrase] as its own sentence, or removes it if already present.
  static String togglePhrase(String text, String phrase) {
    final parts = text
        .split(RegExp(r'\.\s*|\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final i = parts.indexWhere((p) => p.toLowerCase() == phrase.toLowerCase());
    if (i >= 0) {
      parts.removeAt(i);
    } else {
      parts.add(phrase);
    }
    return parts.isEmpty ? '' : '${parts.join('. ')}.';
  }

  static bool hasPhrase(String text, String phrase) => text
      .split(RegExp(r'\.\s*|\n'))
      .any((p) => p.trim().toLowerCase() == phrase.toLowerCase());

  final String description;

  /// Free text. With a [weeklyHours] schedule it is the note beside it
  /// ("Closed on public holidays"); profiles saved before the schedule
  /// existed keep their hours here and still display them.
  final String hours;

  /// The day-by-day schedule; null when the seller has not set one.
  final WeeklyHours? weeklyHours;

  /// Branding accent, as a packed ARGB int so it round-trips Firestore cleanly.
  final int? brandColorValue;
  final String logoUrl;
  final String pickupPolicy;
  final String returnPolicy;
  final List<String> paymentMethods;

  bool get isEmpty =>
      description.trim().isEmpty &&
      hours.trim().isEmpty &&
      (weeklyHours?.isEmpty ?? true) &&
      brandColorValue == null &&
      logoUrl.trim().isEmpty &&
      pickupPolicy.trim().isEmpty &&
      returnPolicy.trim().isEmpty &&
      paymentMethods.isEmpty;

  factory StoreProfile.fromMap(Object? raw) {
    if (raw is! Map) return const StoreProfile();
    List<String> strings(Object? v) => v is List
        ? v
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : const [];
    String text(Object? v) => v is String ? v.trim() : '';
    final color = raw['brandColorValue'];
    return StoreProfile(
      description: text(raw['description']),
      hours: text(raw['hours']),
      weeklyHours: WeeklyHours.fromMap(raw['weeklyHours']),
      brandColorValue: color is num ? color.toInt() : null,
      logoUrl: text(raw['logoUrl']),
      pickupPolicy: text(raw['pickupPolicy']),
      returnPolicy: text(raw['returnPolicy']),
      paymentMethods: strings(raw['paymentMethods']),
    );
  }

  Map<String, Object?> toMap() => {
        'description': description,
        'hours': hours,
        'weeklyHours':
            (weeklyHours == null || weeklyHours!.isEmpty) ? null : weeklyHours!.toMap(),
        'brandColorValue': brandColorValue,
        'logoUrl': logoUrl,
        'pickupPolicy': pickupPolicy,
        'returnPolicy': returnPolicy,
        'paymentMethods': paymentMethods,
      };

  StoreProfile copyWith({
    String? description,
    String? hours,
    WeeklyHours? weeklyHours,
    bool clearWeeklyHours = false,
    int? brandColorValue,
    bool clearBrandColor = false,
    String? logoUrl,
    String? pickupPolicy,
    String? returnPolicy,
    List<String>? paymentMethods,
  }) =>
      StoreProfile(
        description: description ?? this.description,
        hours: hours ?? this.hours,
        weeklyHours:
            clearWeeklyHours ? null : (weeklyHours ?? this.weeklyHours),
        brandColorValue: clearBrandColor
            ? null
            : (brandColorValue ?? this.brandColorValue),
        logoUrl: logoUrl ?? this.logoUrl,
        pickupPolicy: pickupPolicy ?? this.pickupPolicy,
        returnPolicy: returnPolicy ?? this.returnPolicy,
        paymentMethods: paymentMethods ?? this.paymentMethods,
      );
}
