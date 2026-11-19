import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';

class EstimateLine {
  const EstimateLine({
    required this.label,
    required this.price,
    required this.matches,
    this.material,
    this.supplier,
    this.productId,
  });

  final String label;

  final int? price;

  final int matches;

  final String? material;

  final String? supplier;

  final String? productId;

  bool get hasData => price != null;
}

class EstimateOption {
  const EstimateOption({
    required this.productId,
    required this.name,
    required this.supplier,
    required this.price,
    required this.isEcoFriendly,
    required this.inStock,
  });

  final String productId;

  final String name;

  final String? supplier;

  final int price;

  final bool isEcoFriendly;

  final bool inStock;
}

const budgetLineLabels = [
  'Wall Paint',
  'Flooring',
  'Furniture',
  'Lighting',
  'Accessories',
];

const List<List<String>> _budgetLineCategories = [
  ['Paint', 'Wall Covering'],
  ['Flooring'],
  ['Furniture'],
  ['Lighting'],
  ['Decor', 'Textiles'],
];

int? medianPrice(Iterable<int> prices) {
  final sorted = prices.toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

Iterable<Product> _lineProducts(
  List<Product> products,
  int lineIndex, {
  required bool ecoFriendly,
}) sync* {
  final wanted =
      _budgetLineCategories[lineIndex].map((c) => c.toLowerCase()).toSet();
  for (final p in products) {
    if (!p.isActive) continue;
    if (ecoFriendly && !p.isEcoFriendly) continue;
    if (wanted.contains(p.category.trim().toLowerCase())) yield p;
  }
}

String? _supplierName(Product p) {
  final name = p.supplier.name.trim();
  return name.isEmpty ? null : name;
}

List<EstimateLine> buildEstimateLines(
  List<Product> products, {
  required bool ecoFriendly,
}) {
  return [
    for (var i = 0; i < budgetLineLabels.length; i++)
      () {
        Product? cheapest;
        var matches = 0;
        for (final p in _lineProducts(products, i, ecoFriendly: ecoFriendly)) {
          matches++;
          if (cheapest == null || p.price < cheapest.price) cheapest = p;
        }
        if (cheapest == null) {
          return EstimateLine(
            label: budgetLineLabels[i],
            price: null,
            matches: 0,
          );
        }
        return EstimateLine(
          label: budgetLineLabels[i],
          price: cheapest.price,
          matches: matches,
          material: cheapest.name,
          supplier: _supplierName(cheapest),
          productId: cheapest.id,
        );
      }(),
  ];
}

List<EstimateOption> buildLineOptions(
  List<Product> products, {
  required String label,
  required bool ecoFriendly,
}) {
  final index = budgetLineLabels.indexOf(label);
  if (index < 0) return const [];
  final options = [
    for (final p in _lineProducts(products, index, ecoFriendly: ecoFriendly))
      EstimateOption(
        productId: p.id,
        name: p.name,
        supplier: _supplierName(p),
        price: p.price,
        isEcoFriendly: p.isEcoFriendly,
        inStock: !p.isOutOfStock,
      ),
  ];
  return options..sort((a, b) => a.price.compareTo(b.price));
}

class CheaperSwap {
  const CheaperSwap({
    required this.label,
    required this.currentName,
    required this.currentPrice,
    required this.swapProductId,
    required this.swapName,
    required this.swapPrice,
    this.swapSupplier,
  });

  final String label;
  final String currentName;
  final int currentPrice;
  final String swapProductId;
  final String swapName;
  final int swapPrice;
  final String? swapSupplier;

  int get saving => currentPrice - swapPrice;
}

/// Cheaper picks for the categories where the buyer chose something above the
/// cheapest listing (FR26). Only worth suggesting when the estimate is over
/// budget — a swap then is what brings it back under.
List<CheaperSwap> buildCheaperSwaps({
  required List<Product> products,
  required Map<String, String> choices,
  required bool ecoFriendly,
}) {
  final swaps = <CheaperSwap>[];
  for (final label in budgetLineLabels) {
    final options =
        buildLineOptions(products, label: label, ecoFriendly: ecoFriendly);
    if (options.length < 2) continue;
    final chosenId = choices[label];
    if (chosenId == null) continue;
    EstimateOption? chosen;
    for (final o in options) {
      if (o.productId == chosenId) {
        chosen = o;
        break;
      }
    }
    if (chosen == null) continue;
    final cheapest = options.first;
    if (cheapest.productId == chosen.productId) continue;
    if (cheapest.price >= chosen.price) continue;
    swaps.add(CheaperSwap(
      label: label,
      currentName: chosen.name,
      currentPrice: chosen.price,
      swapProductId: cheapest.productId,
      swapName: cheapest.name,
      swapPrice: cheapest.price,
      swapSupplier: cheapest.supplier,
    ));
  }
  // Biggest saving first — swapping the priciest choice helps soonest.
  swaps.sort((a, b) => b.saving.compareTo(a.saving));
  return swaps;
}

int estimateTotal(List<EstimateLine> lines) =>
    lines.fold<int>(0, (sum, l) => sum + (l.price ?? 0));

String buildBudgetReport({
  required String room,
  required int budgetRm,
  required List<EstimateLine> lines,
  required DateTime generatedAt,
  required bool ecoFriendly,
}) {
  final total = estimateTotal(lines);
  final remaining = budgetRm - total;
  final buf = StringBuffer()
    ..writeln('Budget Planner Report — $room')
    ..writeln('Generated ${Formatters.shortDateTime(generatedAt)}')
    ..writeln()
    ..writeln('Budget: ${Formatters.myr(budgetRm)}')
    ..writeln();

  for (final l in lines) {
    buf.writeln(l.hasData
        ? '${l.label}: ${Formatters.myr(l.price!)}'
            '${l.supplier == null ? '' : ' · ${l.supplier}'}'
        : '${l.label}: — (no price data yet)');
  }

  buf
    ..writeln()
    ..writeln('Total estimate: ${Formatters.myr(total)}')
    ..writeln(remaining >= 0
        ? 'Remaining: ${Formatters.myr(remaining)}'
        : 'Over budget by ${Formatters.myr(remaining.abs())}')
    ..writeln()
    ..writeln('Estimates are the lowest prices across active marketplace '
        'listings'
        '${ecoFriendly ? ' (eco-friendly listings only)' : ''}.')
    ..writeln('A line shows "—" when the catalogue has no matching listing yet.');

  return buf.toString();
}

// ── Budget alerts (FR25: "approach or exceed") ──────────────────────────────

enum BudgetStatus { noBudget, comfortable, approaching, over }

/// Share of the budget at which the planner starts warning.
const double budgetWarnAt = 0.9;

BudgetStatus budgetStatus({required num total, required num budget}) {
  if (budget <= 0) return BudgetStatus.noBudget;
  if (total > budget) return BudgetStatus.over;
  if (total >= budget * budgetWarnAt) return BudgetStatus.approaching;
  return BudgetStatus.comfortable;
}
