import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../models/store_profile.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/float_button.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/marketplace/presentation/providers/marketplace_providers.dart';
import '../../../settings/presentation/widgets/settings_widgets.dart';

// Storefront details buyers see on a seller's listings: how they trade,
// when they are open, what they accept, and their own policies (report:
// "manage their profiles and store details, including contact info,
// business hours, and branding" and "set store policies").
class StoreProfileScreen extends ConsumerStatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  ConsumerState<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends ConsumerState<StoreProfileScreen> {
  late final TextEditingController _description;
  late final TextEditingController _hours;
  late final TextEditingController _pickup;
  late final TextEditingController _returns;
  late StoreProfile _draft;
  bool _saving = false;
  bool _loaded = false;

  static const _swatches = <Color>[
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF00838F),
  ];

  @override
  void initState() {
    super.initState();
    _draft = const StoreProfile();
    _description = TextEditingController();
    _hours = TextEditingController();
    _pickup = TextEditingController();
    _returns = TextEditingController();
  }

  // The signed-in user arrives on a stream; seeding from initState would
  // read null and a later save would wipe the stored profile.
  void _seedFrom(StoreProfile profile) {
    if (_loaded) return;
    _loaded = true;
    _draft = profile;
    _description.text = profile.description;
    _hours.text = profile.hours;
    _pickup.text = profile.pickupPolicy;
    _returns.text = profile.returnPolicy;
  }

  @override
  void dispose() {
    _description.dispose();
    _hours.dispose();
    _pickup.dispose();
    _returns.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final profile = _draft.copyWith(
      description: _description.text.trim(),
      hours: _hours.text.trim(),
      pickupPolicy: _pickup.text.trim(),
      returnPolicy: _returns.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await ref.read(authStateProvider.notifier).updateProfile(
            name: user.name,
            phone: user.phone,
            address: user.address,
            businessName: user.businessName,
            businessPhone: user.businessPhone,
            businessAddress: user.businessAddress,
            storeProfile: profile,
          );
      var reachedListings = true;
      try {
        await ref
            .read(marketplaceRepositoryProvider)
            .syncStoreProfile(user.uid, profile);
      } catch (_) {
        reachedListings = false;
      }
      if (!mounted) return;
      showAppSnackbar(
        context,
        reachedListings
            ? 'Store profile saved'
            : 'Saved, but your listings could not be updated yet. '
                'Save again to retry.',
        isError: !reachedListings,
      );
      if (!reachedListings) return;
      // Through the router, not Navigator.pop: the save re-emits the user and
      // refreshes routing, and a raw pop let that refresh put this page back.
      leaveSettings(context, ref);
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context,
            userMessage(e, fallback: 'Could not save your store profile.'),
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user != null) _seedFrom(user.storeProfile);
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          key: const Key('save-store-profile'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            minimumSize: const Size.fromHeight(50),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save store profile'),
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
              title: 'Store profile',
              subtitle: 'What buyers see about how you trade',
            ),
            const SizedBox(height: 16),
            _card(
              'Branding',
              [
                _field(
                  key: 'store-description',
                  label: 'Store description',
                  hint: 'What you sell and what makes your store different',
                  controller: _description,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Text('Brand colour',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _swatches)
                      _swatch(
                        c,
                        selected: _draft.brandColorValue == c.toARGB32(),
                        onTap: () => setState(() => _draft = _draft.copyWith(
                            brandColorValue: c.toARGB32())),
                      ),
                    _swatch(
                      null,
                      selected: _draft.brandColorValue == null,
                      onTap: () => setState(() =>
                          _draft = _draft.copyWith(clearBrandColor: true)),
                    ),
                  ],
                ),
              ],
            ),
            _card(
              'Business hours',
              [
                _field(
                  key: 'store-hours',
                  label: 'When you are open',
                  hint: 'e.g. Mon–Fri 9:00–18:00, Sat 10:00–14:00',
                  controller: _hours,
                  maxLines: 2,
                ),
              ],
            ),
            _card(
              'Accepted payment options',
              [
                Text(
                  'How buyers may pay you. Card payments are handled by '
                  'Stripe at checkout.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                for (final option in StoreProfile.paymentOptions)
                  CheckboxListTile(
                    key: Key('pay-${option.replaceAll(' ', '-')}'),
                    value: _draft.paymentMethods.contains(option),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.accent,
                    title: Text(option, style: GoogleFonts.poppins(fontSize: 14)),
                    onChanged: (v) => setState(() {
                      final list = [..._draft.paymentMethods];
                      if (v == true) {
                        if (!list.contains(option)) list.add(option);
                      } else {
                        list.remove(option);
                      }
                      _draft = _draft.copyWith(paymentMethods: list);
                    }),
                  ),
              ],
            ),
            _card(
              'Policies',
              [
                _field(
                  key: 'store-pickup-policy',
                  label: 'Pickup / collection policy',
                  hint: 'e.g. Collect within 7 days, bring your order number',
                  controller: _pickup,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _field(
                  key: 'store-return-policy',
                  label: 'Returns & exchanges',
                  hint: 'e.g. 14-day returns on unused items with the receipt',
                  controller: _returns,
                  maxLines: 3,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        // Material, not a decorated Container: ListTile paints its splash on
        // the nearest Material, and a bare DecoratedBox hides it.
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border),
          ),
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _field({
    required String key,
    required String label,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
  }) =>
      TextField(
        key: Key(key),
        controller: controller,
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _swatch(Color? color, {required bool selected, required VoidCallback onTap}) {
    final isClear = color == null;
    return InkWell(
      key: Key('swatch-${isClear ? 'clear' : color.toARGB32()}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isClear ? AppColors.surfaceContainer : color,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: isClear
            ? Icon(Icons.block, size: 20, color: AppColors.textSecondary)
            : selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
      ),
    );
  }
}
