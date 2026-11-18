// Batch product upload (report: "supports batch uploads for product
// management"). One row per product; the header names the columns so a
// supplier can build the sheet in Excel. Nothing is published silently —
// every row is validated first and only clean rows are imported.
class BulkProductRow {
  const BulkProductRow({
    required this.line,
    this.name,
    this.category,
    this.designStyle,
    this.description,
    this.price,
    this.stock,
    this.widthM,
    this.heightM,
    this.depthM,
    this.ecoFriendly = false,
    this.imageUrl,
    this.error,
  });

  final int line;
  final String? name;
  final String? category;
  final String? designStyle;
  final String? description;
  final int? price;
  final int? stock;
  final double? widthM;
  final double? heightM;
  final double? depthM;
  final bool ecoFriendly;
  final String? imageUrl;
  final String? error;

  bool get isValid => error == null;
}

class BulkProductImport {
  static const requiredColumns = [
    'name',
    'category',
    'designstyle',
    'description',
    'price',
    'stock',
  ];

  static const optionalColumns = [
    'width',
    'height',
    'depth',
    'eco',
    'imageurl',
  ];

  // Same limits as the Add Product form, so a CSV cannot publish what the
  // form would refuse.
  static const minNameChars = 3;
  static const maxNameChars = 80;
  static const minDescriptionChars = 20;
  static const maxDescriptionChars = 500;
  static const minSizeM = 0.1;
  static const maxSizeM = 10.0;

  /// Header row maps columns by name (case-insensitive). Missing optional
  /// columns are fine; a missing required one fails the whole file, because
  /// guessing which column is which would create wrong listings.
  ///
  /// [categories] / [styles] are the marketplace's own lists: a value must
  /// match one (any letter case) and is stored with the list's spelling, so
  /// a typo cannot create a category no filter shows. Null skips the check.
  static List<BulkProductRow> parse(
    String csvText, {
    List<String>? categories,
    List<String>? styles,
  }) {
    final rows = _rows(csvText);
    if (rows.isEmpty) return const [];
    final header = [
      for (final cell in rows.first) cell.trim().toLowerCase(),
    ];
    final missing = requiredColumns.where((c) => !header.contains(c)).toList();
    if (missing.isNotEmpty) {
      return [
        BulkProductRow(
          line: 1,
          error: 'Missing column(s): ${missing.join(', ')}. '
              'A header row is required.',
        ),
      ];
    }

    int? col(String name) {
      final i = header.indexOf(name);
      return i < 0 ? null : i;
    }

    final out = <BulkProductRow>[];
    for (var r = 1; r < rows.length; r++) {
      final cells = rows[r];
      if (cells.every((c) => c.trim().isEmpty)) continue;
      String? at(String? index) {
        if (index == null) return null;
        final i = int.parse(index);
        return i < cells.length ? cells[i].trim() : null;
      }

      String? str(String name) {
        final v = at(col(name)?.toString());
        return (v == null || v.isEmpty) ? null : v;
      }

      // Whole numbers only. Currency marks, spaces and thousands commas are
      // dropped, and "450.00" counts as 450 — but the decimal point is never
      // silently deleted ("450.50" or "5.5" are refused, not read as 45050).
      int? integer(String name) {
        final v = str(name);
        if (v == null) return null;
        final cleaned =
            v.replaceAll(RegExp(r'rm|\s|,', caseSensitive: false), '');
        final n = num.tryParse(cleaned);
        if (n == null || !n.isFinite || n != n.roundToDouble()) return null;
        return n.toInt();
      }

      double? decimal(String name) {
        final v = str(name);
        if (v == null) return null;
        return double.tryParse(
            v.replaceAll(RegExp(r'\s|m$', caseSensitive: false), ''));
      }

      // Unknown values stay as typed so _validate can name them.
      String? canonical(String? value, List<String>? known) {
        if (value == null || known == null) return value;
        for (final k in known) {
          if (k.toLowerCase() == value.toLowerCase()) return k;
        }
        return value;
      }

      final row = BulkProductRow(
        line: r + 1,
        name: str('name'),
        category: canonical(str('category'), categories),
        designStyle: canonical(str('designstyle'), styles),
        description: str('description'),
        price: integer('price'),
        stock: integer('stock'),
        widthM: decimal('width'),
        heightM: decimal('height'),
        depthM: decimal('depth'),
        ecoFriendly: (str('eco') ?? '').toLowerCase() == 'true',
        imageUrl: str('imageurl'),
      );
      out.add(_validate(row, categories: categories, styles: styles));
    }
    return out;
  }

  static BulkProductRow _validate(
    BulkProductRow r, {
    List<String>? categories,
    List<String>? styles,
  }) {
    String? problem;
    final name = r.name;
    final description = r.description;
    if (name == null) {
      problem = 'Name is missing';
    } else if (name.length < minNameChars) {
      problem = 'Name needs at least $minNameChars characters';
    } else if (name.length > maxNameChars) {
      problem = 'Name is longer than $maxNameChars characters';
    } else if (r.category == null) {
      problem = 'Category is missing';
    } else if (categories != null && !categories.contains(r.category)) {
      problem = 'Unknown category "${r.category}". '
          'Use one of: ${categories.join(', ')}';
    } else if (r.designStyle == null) {
      problem = 'Design style is missing';
    } else if (styles != null && !styles.contains(r.designStyle)) {
      problem = 'Unknown design style "${r.designStyle}". '
          'Use one of: ${styles.join(', ')}';
    } else if (description == null ||
        description.length < minDescriptionChars) {
      problem = 'Description needs at least $minDescriptionChars characters';
    } else if (description.length > maxDescriptionChars) {
      problem = 'Description is longer than $maxDescriptionChars characters';
    } else if (r.price == null) {
      problem = 'Price must be a whole number of RM';
    } else if (r.price! <= 0) {
      problem = 'Price must be above RM 0';
    } else if (r.stock == null || r.stock! < 0) {
      problem = 'Stock must be a whole number, 0 or more';
    } else {
      for (final (label, value) in [
        ('Width', r.widthM),
        ('Height', r.heightM),
        ('Depth', r.depthM),
      ]) {
        if (value != null && (value < minSizeM || value > maxSizeM)) {
          problem = '$label must be between $minSizeM and ${maxSizeM.toInt()} '
              'metres';
          break;
        }
      }
      // A size is only useful to AR when all three are given; a partial set
      // would make the AR model come out at a guessed size.
      if (problem == null) {
        final given = [r.widthM, r.heightM, r.depthM].whereType<double>().length;
        if (given != 0 && given != 3) {
          problem = 'Give width, height and depth together, or leave all blank';
        }
      }
    }
    if (problem == null) return r;
    return BulkProductRow(
      line: r.line,
      name: r.name,
      category: r.category,
      designStyle: r.designStyle,
      description: r.description,
      price: r.price,
      stock: r.stock,
      widthM: r.widthM,
      heightM: r.heightM,
      depthM: r.depthM,
      ecoFriendly: r.ecoFriendly,
      imageUrl: r.imageUrl,
      error: problem,
    );
  }

  /// Handles quoted cells (a description containing a comma) and CRLF.
  static List<List<String>> _rows(String text) {
    final out = <List<String>>[];
    var cells = <String>[];
    var cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        cells.add(cell.toString());
        cell = StringBuffer();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        cells.add(cell.toString());
        cell = StringBuffer();
        out.add(cells);
        cells = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || cells.isNotEmpty) {
      cells.add(cell.toString());
      out.add(cells);
    }
    return out;
  }
}
