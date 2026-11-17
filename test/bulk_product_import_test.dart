import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/supplier/data/bulk_product_import.dart';

const header =
    'name,category,designStyle,description,price,stock,width,height,depth,eco,imageUrl';

String row(List<String> cells) => cells.join(',');

/// Newline built at runtime so the CSV fixtures stay readable in source.
final String _nl = String.fromCharCode(10);
final String _crlf = String.fromCharCode(13) + String.fromCharCode(10);
final String _blank = _nl + _nl;

void main() {
  group('BulkProductImport.parse', () {
    test('reads a well-formed file and keeps typed numbers', () {
      final rows = BulkProductImport.parse([
        header,
        row([
          'Oak Console Table', 'Furniture', 'Classic',
          'Solid oak console table with two drawers and a lower shelf',
          '450', '4', '1.2', '0.8', '0.35', 'true',
          'https://cdn.example.com/oak.jpg',
        ]),
        row([
          'Wall Paint', 'Paint', 'Modern',
          'Low odour matt emulsion for interior walls and ceilings',
          '30', '12', '', '', '', 'false', '',
        ]),
      ].join(_nl));

      expect(rows, hasLength(2));
      expect(rows.every((r) => r.isValid), isTrue);
      expect(rows[0].price, 450);
      expect(rows[0].stock, 4);
      expect(rows[0].widthM, 1.2);
      expect(rows[0].ecoFriendly, isTrue);
      expect(rows[0].imageUrl, 'https://cdn.example.com/oak.jpg');
      expect(rows[1].ecoFriendly, isFalse);
      expect(rows[1].widthM, isNull);
    });

    test('a missing required column fails the file, not the rows', () {
      final rows = BulkProductImport.parse(['name,price', 'Sofa,100'].join(_nl));
      expect(rows, hasLength(1));
      expect(rows.single.isValid, isFalse);
      expect(rows.single.error, contains('Missing column'));
      expect(rows.single.error, contains('stock'));
    });

    test('missing optional columns are fine', () {
      final rows = BulkProductImport.parse([
        'name,category,designStyle,description,price,stock',
        row([
          'Rug', 'Textiles', 'Bohemian',
          'Hand woven wool rug with a soft pile underfoot', '250', '3',
        ]),
      ].join(_nl));
      expect(rows.single.isValid, isTrue);
    });

    test('each bad row explains itself without blocking the good ones', () {
      final rows = BulkProductImport.parse([
        header,
        row(['', 'Furniture', 'Modern', 'A perfectly fine description here', '10', '1']),
        row(['Sofa', 'Furniture', 'Modern', 'A perfectly fine description here', 'abc', '1']),
        row(['Chair', 'Furniture', 'Modern', 'A perfectly fine description here', '50', '-2']),
        row(['Lamp', 'Lighting', 'Modern', 'too short', '20', '3']),
        row(['Table', 'Furniture', 'Modern', 'A perfectly fine description here', '9', '1', '1', '', '']),
        row(['Good', 'Furniture', 'Modern', 'A perfectly fine description here', '9', '1']),
      ].join(_nl));

      final valid = rows.where((r) => r.isValid).toList();
      expect(valid.map((r) => r.name), ['Good']);
      expect(rows[0].error, contains('Name is missing'));
      expect(rows[1].error, contains('Price'));
      expect(rows[2].error, contains('Stock'));
      expect(rows[3].error, contains('Description'));
      expect(rows[4].error, contains('width, height and depth together'));
    });

    test('a partial size is refused rather than guessed', () {
      final rows = BulkProductImport.parse([
        header,
        row(['Bed', 'Furniture', 'Modern', 'A perfectly fine description here', '9', '1', '2', '1.5', '']),
      ].join(_nl));
      expect(rows.single.isValid, isFalse);
      expect(rows.single.error, contains('width, height and depth together'));
    });

    test('quotes and commas inside a description survive', () {
      final rows = BulkProductImport.parse([
        header,
        'Wardrobe,Furniture,Classic,"Tall, double-door wardrobe with a mirror",300,2,,,,false,',
      ].join(_nl));
      expect(rows.single.isValid, isTrue);
      expect(rows.single.description, 'Tall, double-door wardrobe with a mirror');
    });

    test('blank rows are skipped and CRLF is handled', () {
      final rows = BulkProductImport.parse([
        header,
        '',
        row(['Sofa', 'Furniture', 'Modern', 'A perfectly fine description here', '10', '1']),
        ',,,,,',
      ].join(_crlf));
      expect(rows, hasLength(1));
      expect(rows.single.isValid, isTrue);
    });

    test('a headerless file says so instead of inventing columns', () {
      expect(BulkProductImport.parse(''), isEmpty);
      final blank = BulkProductImport.parse(_blank);
      expect(blank, hasLength(1));
      expect(blank.single.error, contains('Missing column'),
          reason: 'a blank header is not a usable file — say so clearly');
    });
  });
}
