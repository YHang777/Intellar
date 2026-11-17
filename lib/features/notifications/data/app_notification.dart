class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.data = const {},
    this.read = false,
    this.createdAt,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final Map<String, String> data;
  final bool read;
  final DateTime? createdAt;

  String? get orderId => _nonEmpty(data['orderId']);
  String? get quoteId => _nonEmpty(data['quoteId']);
  String? get productId => _nonEmpty(data['productId']);

  static String? _nonEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v;

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    final rawData = map['data'];
    final data = <String, String>{};
    if (rawData is Map) {
      rawData.forEach((k, v) {
        if (v != null) data[k.toString()] = v.toString();
      });
    }
    return AppNotification(
      id: id,
      kind: map['kind']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      data: data,
      read: map['read'] == true,
      createdAt: _date(map['createdAt']),
    );
  }

  static DateTime? _date(dynamic v) {
    if (v is DateTime) return v;
    try {
      final toDate = v?.toDate;
      if (toDate is Function) {
        final d = v.toDate();
        if (d is DateTime) return d;
      }
    } catch (_) {}
    return v is String ? DateTime.tryParse(v) : null;
  }
}

// Where tapping a notification (in the inbox or the system tray) leads.
String? routeForNotification({
  required bool isSupplier,
  String? orderId,
  String? quoteId,
  String? productId,
}) {
  if (orderId != null) {
    return isSupplier ? '/supplier/orders/$orderId' : '/marketplace/orders/$orderId';
  }
  if (quoteId != null) {
    return isSupplier ? '/supplier/quotes/$quoteId' : '/marketplace/orders?tab=quotes';
  }
  if (productId != null && !isSupplier) return '/marketplace/product/$productId';
  return null;
}
