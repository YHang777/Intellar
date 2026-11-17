// A seller's storefront: what buyers see about how they trade (report:
// "manage their profiles and store details, including contact info, business
// hours, and branding" and "set store policies" / "accepted payment options").
// Money still moves through Stripe — these are the seller's own terms.
class StoreProfile {
  const StoreProfile({
    this.description = '',
    this.hours = '',
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

  final String description;
  final String hours;

  /// Branding accent, as a packed ARGB int so it round-trips Firestore cleanly.
  final int? brandColorValue;
  final String logoUrl;
  final String pickupPolicy;
  final String returnPolicy;
  final List<String> paymentMethods;

  bool get isEmpty =>
      description.trim().isEmpty &&
      hours.trim().isEmpty &&
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
        'brandColorValue': brandColorValue,
        'logoUrl': logoUrl,
        'pickupPolicy': pickupPolicy,
        'returnPolicy': returnPolicy,
        'paymentMethods': paymentMethods,
      };

  StoreProfile copyWith({
    String? description,
    String? hours,
    int? brandColorValue,
    String? logoUrl,
    String? pickupPolicy,
    String? returnPolicy,
    List<String>? paymentMethods,
  }) =>
      StoreProfile(
        description: description ?? this.description,
        hours: hours ?? this.hours,
        brandColorValue: brandColorValue ?? this.brandColorValue,
        logoUrl: logoUrl ?? this.logoUrl,
        pickupPolicy: pickupPolicy ?? this.pickupPolicy,
        returnPolicy: returnPolicy ?? this.returnPolicy,
        paymentMethods: paymentMethods ?? this.paymentMethods,
      );
}
