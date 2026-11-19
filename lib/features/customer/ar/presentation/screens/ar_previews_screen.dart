import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../data/ar_previews.dart';

final arPreviewStoreProvider =
    Provider<ArPreviewStore>((ref) => ArPreviewStore());

final arPreviewsProvider = FutureProvider<List<ArPreview>>((ref) async {
  return ref.watch(arPreviewStoreProvider).list();
});

// Saved AR previews: browse them, share any one, or pick two to view side by
// side before choosing between materials or pieces (FR14).
class ArPreviewsScreen extends ConsumerStatefulWidget {
  const ArPreviewsScreen({super.key});

  @override
  ConsumerState<ArPreviewsScreen> createState() => _ArPreviewsScreenState();
}

class _ArPreviewsScreenState extends ConsumerState<ArPreviewsScreen> {
  bool _comparing = false;
  final Set<String> _selected = {};

  ArPreviewStore get _store => ref.read(arPreviewStoreProvider);

  Future<void> _share(ArPreview preview) async {
    try {
      await _store.share(preview);
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context,
            userMessage(e, fallback: 'Could not share that preview.'),
            isError: true);
      }
    }
  }

  Future<bool> _delete(ArPreview preview) async {
    final ok = await showConfirmDialogLocal(context, preview.label);
    if (!ok || !mounted) return false;
    await _store.delete(preview.id);
    setState(() => _selected.remove(preview.id));
    ref.invalidate(arPreviewsProvider);
    if (mounted) showAppSnackbar(context, 'Photo deleted');
    return true;
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) {
        _selected.remove(id);
      } else if (_selected.length > 2) {
        _selected.remove(_selected.first);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(arPreviewsProvider);
    final previews = async.valueOrNull ?? const <ArPreview>[];
    final compare = _comparing && _selected.length == 2;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const FloatingBackButton(),
                  const Spacer(),
                  if (previews.length >= 2)
                    TextButton(
                      key: const Key('ar-preview-compare'),
                      onPressed: () => setState(() {
                        _comparing = !_comparing;
                        _selected.clear();
                      }),
                      child: Text(_comparing ? 'Cancel' : 'Compare'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: PageHeading(
                title: _comparing ? 'Pick two to compare' : 'AR previews',
                subtitle: _comparing
                    ? 'Tap two previews to see them side by side'
                    : '${previews.length} saved on this device',
              ),
            ),
            if (compare)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton(
                  key: const Key('ar-preview-do-compare'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: () => context.mounted
                      ? Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _CompareView(
                              store: _store,
                              previews: previews
                                  .where((p) => _selected.contains(p.id))
                                  .toList(),
                            ),
                          ),
                        )
                      : null,
                  child: const Text('Compare 2 previews'),
                ),
              ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => EmptyState(
                  icon: Icons.broken_image_outlined,
                  title: 'Could not load previews',
                  subtitle: 'Something went wrong reading this device.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(arPreviewsProvider),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState(
                        icon: Icons.view_in_ar,
                        title: 'No previews yet',
                        subtitle:
                            'Open AR and tap Save preview to keep a shot of a '
                            'material or piece. You can share it or compare '
                            'two side by side.',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final chosen = _selected.contains(p.id);
                          return _PreviewCard(
                            preview: p,
                            comparing: _comparing,
                            selected: chosen,
                            onTap: () => _comparing
                                ? _toggle(p.id)
                                : _open(context, p),
                            onShare: () => _share(p),
                            onDelete: () => _delete(p),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, ArPreview preview) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (detail) => _PreviewDetail(
          preview: preview,
          onShare: () => _share(preview),
          onDelete: () async {
            // Close the photo once it is gone instead of showing a ghost.
            if (await _delete(preview) && detail.mounted) {
              Navigator.of(detail).pop();
            }
          },
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.comparing,
    required this.selected,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  final ArPreview preview;
  final bool comparing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('ar-preview-${preview.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(preview.path), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                          color: AppColors.surfaceContainer)),
                  if (comparing && selected)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.accent,
                        child: Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preview.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(Formatters.shortDateTime(preview.createdAt),
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: AppColors.textHint)),
                      ],
                    ),
                  ),
                  if (!comparing)
                    PopupMenuButton<String>(
                      key: Key('ar-preview-menu-${preview.id}'),
                      tooltip: 'Photo options',
                      icon: Icon(Icons.more_vert,
                          size: 20, color: AppColors.textSecondary),
                      onSelected: (v) => v == 'delete' ? onDelete() : onShare(),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share_outlined),
                            title: Text('Share'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline,
                                color: AppColors.error),
                            title: Text('Delete',
                                style: TextStyle(color: AppColors.error)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewDetail extends StatelessWidget {
  const _PreviewDetail({
    required this.preview,
    required this.onShare,
    required this.onDelete,
  });

  final ArPreview preview;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const FloatingBackButton(),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(File(preview.path), fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.broken_image,
                            size: 64, color: AppColors.textHint))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(preview.label,
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(Formatters.shortDateTime(preview.createdAt),
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('ar-preview-share'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent),
                          onPressed: onShare,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('ar-preview-delete'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(color: AppColors.error)),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView({required this.previews, required this.store});

  final List<ArPreview> previews;
  final ArPreviewStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FloatingBackButton(),
              ),
            ),
            const SizedBox(height: 4),
            Text('Compare',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in previews) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(p.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(File(p.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(
                                            color:
                                                AppColors.surfaceContainer)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (p != previews.last)
                      const VerticalDivider(width: 1),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('compare-share'),
                      onPressed: () {
                        for (final p in previews) {
                          store.share(p).catchError((Object e) {
                            debugPrint('[ar-previews] share failed: $e');
                          });
                        }
                      },
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share both'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialogLocal(BuildContext context, String label) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete this photo?'),
      content: Text('"$label" will be removed from this device.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}
