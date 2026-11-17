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

  static const minDescriptionChars = 20;

  /// Header row maps columns by name (case-insensitive). Missing optional
  /// columns are fine; a missing required one fails the whole file, because
  /// guessing which column is which would create wrong listings.
  static List<BulkProductRow> parse(String csvText) {
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

      int? integer(String name) {
        final v = str(name);
        if (v == null) return null;
        final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9-]'), ''));
        return n;
      }

      double? decimal(String name) {
        final v = str(name);
        if (v == null) return null;
        return double.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), ''));
      }

      final row = BulkProductRow(
        line: r + 1,
        name: str('name'),
        category: str('category'),
        designStyle: str('designstyle'),
        description: str('description'),
        price: integer('price'),
        stock: integer('stock'),
        widthM: decimal('width'),
        heightM: decimal('height'),
        depthM: decimal('depth'),
        ecoFriendly: (str('eco') ?? '').toLowerCase() == 'true',
        imageUrl: str('imageurl'),
      );
      out.add(_validate(row));
    }
    return out;
  }

  static BulkProductRow _validate(BulkProductRow r) {
    String? problem;
    if (r.name == null || r.name!.length < 2) {
      problem = 'Name is missing';
    } else if (r.category == null) {
      problem = 'Category is missing';
    } else if (r.designStyle == null) {
      problem = 'Design style is missing';
    } else if (r.description == null ||
        r.description!.length < minDescriptionChars) {
      problem = 'Description needs at least $minDescriptionChars characters';
    } else if (r.price == null || r.price! < 0) {
      problem = 'Price is missing or not a number';
    } else if (r.stock == null || r.stock! < 0) {
      problem = 'Stock is missing or not a whole number';
    } else {
      for (final (label, value) in [
        ('Width', r.widthM),
        ('Height', r.heightM),
        ('Depth', r.depthM),
      ]) {
        if (value != null && (value <= 0 || value > 100)) {
          problem = '$label must be between 0 and 100 metres';
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
