class Formatters {
  Formatters._();

  static String formatOrderNumber(String orderNumber) {
    final n = orderNumber.trim();
    if (n.isEmpty) return '—';
    return n;
  }

  static String myr(int amount) {
    final formatted = amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return 'RM $formatted';
  }

  static String myrDecimal(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return 'RM $whole.${parts[1]}';
  }

  static String phone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = '6$digits';
    if (!digits.startsWith('60')) return raw.trim();
    final national = digits.substring(2);
    if (national.length == 9) {
      return '+60 ${national.substring(0, 2)}-'
          '${national.substring(2, 5)} ${national.substring(5)}';
    }
    if (national.length == 10) {
      return '+60 ${national.substring(0, 2)}-'
          '${national.substring(2, 6)} ${national.substring(6)}';
    }
    return raw.trim();
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String shortDate(DateTime d) {
    d = d.toLocal();
    return '${d.day.toString().padLeft(2, '0')} '
        '${_months[d.month - 1]} ${d.year}';
  }

  static String shortDateTime(DateTime d) {
    d = d.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${shortDate(d)} · $hh:$mm';
  }

  static String monthShort(int month) => _months[month - 1];

  static String greeting([DateTime? at]) => switch ((at ?? DateTime.now()).hour) {
        >= 5 && < 12 => 'Good Morning',
        >= 12 && < 18 => 'Good Afternoon',
        _ => 'Good Evening',
      };
}
