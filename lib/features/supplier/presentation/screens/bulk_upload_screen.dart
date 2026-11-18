import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/float_button.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';
import '../../data/bulk_product_import.dart';

// Batch product upload: pick a CSV, review every row's verdict, then import
// the clean ones (report: "supports batch uploads for product management").
class BulkUploadScreen extends ConsumerStatefulWidget {
  const BulkUploadScreen({super.key});

  @override
  ConsumerState<BulkUploadScreen> createState() => _BulkUploadScreenState();
}

class _BulkUploadScreenState extends ConsumerState<BulkUploadScreen> {
  List<BulkProductRow> _rows = const [];
  String? _fileName;
  bool _importing = false;

  List<BulkProductRow> get _valid => [for (final r in _rows) if (r.isValid) r];
  List<BulkProductRow> get _bad => [for (final r in _rows) if (!r.isValid) r];

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    final file = picked.firstOrNull;
    if (file == null) return;
    final path = file.path;
    if (path == null) {
      if (mounted) {
        showAppSnackbar(context, 'That file could not be read.',
            isError: true);
      }
      return;
    }
    final String text;
    try {
      text = await File(path).readAsString();
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'That file could not be read.',
            isError: true);
      }
      return;
    }
    // The marketplace's own lists, so each row's category and style are
    // checked like the form's dropdowns. If they cannot load, the import
    // refuses rather than guessing.
    final List<String> categories;
    final List<String> styles;
    try {
      categories = [
        for (final c in await ref.read(categoriesProvider.future)) c.name,
      ];
      styles = await ref.read(stylesProvider.future);
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context,
            'Could not load categories. Check your connection and try again.',
            isError: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _fileName = file.name;
      _rows = BulkProductImport.parse(text,
          categories: categories.isEmpty ? null : categories,
          styles: styles.isEmpty ? null : styles);
    });
  }

  Future<void> _import() async {
    final supplier = ref.read(currentSupplierProvider);
    final user = ref.read(currentUserProvider);
    if (supplier == null || user == null) {
      showAppSnackbar(context, 'You must be signed in to import.',
          isError: true);
      return;
    }
    final rows = _valid;
    if (rows.isEmpty) return;
    setState(() => _importing = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    var ok = 0;
    var failed = 0;
    for (final row in rows) {
      final dims = row.widthM == null
          ? null
          : ProductDimensions(
              widthM: row.widthM!,
              heightM: row.heightM!,
              depthM: row.depthM!,
            );
      try {
        await repo.createProduct(Product(
          id: '',
          name: row.name!.trim(),
          price: row.price!,
          stock: row.stock!,
          image: row.imageUrl ?? '',
          images: [if ((row.imageUrl ?? '').isNotEmpty) row.imageUrl!],
          description: row.description!.trim(),
          designStyle: row.designStyle!.trim(),
          category: row.category!.trim(),
          supplier: supplier,
          supplierId: supplier.id,
          isEcoFriendly: row.ecoFriendly,
          dimensions: dims,
        ));
        ok++;
      } catch (e) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    showAppSnackbar(
      context,
      failed == 0
          ? 'Imported $ok product${ok == 1 ? '' : 's'}'
          : 'Imported $ok of ${rows.length} — $failed could not be saved',
      isError: failed > 0,
    );
    if (failed == 0 && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          key: const Key('bulk-import'),
          onPressed: _importing || _valid.isEmpty ? null : _import,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            minimumSize: const Size.fromHeight(50),
          ),
          child: _importing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('Import ${_valid.length} product'
                  '${_valid.length == 1 ? '' : 's'}'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const Align(
                alignment: Alignment.centerLeft, child: FloatingBackButton()),
            const SizedBox(height: 8),
            const PageHeading(
              title: 'Bulk upload',
              subtitle: 'Add many products at once from a CSV file',
            ),
            const SizedBox(height: 12),
            _howItWorks(),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('pick-csv'),
              onPressed: _pick,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_fileName ?? 'Choose a CSV file'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  _count('Ready', _valid.length, AppColors.success),
                  const SizedBox(width: 10),
                  _count('Needs fixing', _bad.length, AppColors.error),
                ],
              ),
              const SizedBox(height: 12),
              for (final row in _rows) _rowCard(row),
            ],
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int n, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text('$n $label',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ),
      );

  Widget _rowCard(BulkProductRow row) {
    final ok = row.isValid;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: ok ? AppColors.border : AppColors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error,
              size: 20, color: ok ? AppColors.success : AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${row.line} · ${row.name ?? '(no name)'}',
                    style: GoogleFonts.poppins(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  ok
                      ? '${row.category} · ${row.designStyle} · '
                          '${Formatters.myr(row.price!)} · ${row.stock!} in stock'
                      : row.error!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: ok ? AppColors.textSecondary : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What the file needs',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'One row per product, with a header row. Required columns: '
              '${BulkProductImport.requiredColumns.join(', ')}. Optional: '
              '${BulkProductImport.optionalColumns.join(', ')} '
              '(set eco to true for an eco-friendly listing).',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Imported listings appear on the marketplace right away. '
              'Add photos afterwards to give each one a 3D model.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textHint, height: 1.5),
            ),
          ],
        ),
      );
}
