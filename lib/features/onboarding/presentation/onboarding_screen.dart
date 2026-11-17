import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/presentation/providers/auth_providers.dart';

class OnboardingSlide {
  const OnboardingSlide(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const homeownerSlides = [
  OnboardingSlide(Icons.view_in_ar, 'Scan your room',
      'Point your camera at the floor and walls. We find the surfaces so you can try new floors, paint and furniture in AR.'),
  OnboardingSlide(Icons.threed_rotation, 'Plan it in 3D',
      'Lay out furniture at true size in the room planner, then walk through the room before you buy.'),
  OnboardingSlide(Icons.auto_awesome, 'Ask the design assistant',
      'Chat about styles, colours and layouts. It knows your room, budget and the live catalogue.'),
  OnboardingSlide(Icons.storefront_outlined, 'Shop and stay on budget',
      'Buy from local sellers, set a budget and see your estimate update as you go.'),
  OnboardingSlide(Icons.palette_outlined, 'Make it yours',
      'Tell us the styles, colours and materials you like so suggestions fit your taste.'),
];

const supplierSlides = [
  OnboardingSlide(Icons.inventory_2_outlined, 'List your products',
      'Add photos, prices, stock and dimensions. We build a true-size 3D model so buyers can see it in their room.'),
  OnboardingSlide(Icons.receipt_long_outlined, 'Handle orders',
      'Confirm orders, mark them ready for collection and keep buyers updated.'),
  OnboardingSlide(Icons.insights_outlined, 'Track your sales',
      'See revenue, top products and low stock, and export sales reports as PDF.'),
  OnboardingSlide(Icons.verified_outlined, 'Get verified',
      'Apply for a verified badge from your profile to build buyer trust.'),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish({bool openPreferences = false}) async {
    final user = ref.read(currentUserProvider);
    final replay = user?.onboardingCompleted ?? true;
    final router = GoRouter.of(context);
    await ref.read(authStateProvider.notifier).completeOnboarding();
    if (!mounted) return;
    final home = (user?.isSupplier ?? false) ? '/supplier/dashboard' : '/home';
    if (replay && router.canPop()) {
      router.pop();
    } else {
      router.go(home);
    }
    if (openPreferences) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => router.push('/settings/preferences'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final slides = (user?.isSupplier ?? false) ? supplierSlides : homeownerSlides;
    final last = _index == slides.length - 1;
    final showPrefs = last && !(user?.isSupplier ?? false);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('onboarding-skip'),
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(slide: slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.accent : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    key: const Key('onboarding-next'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      if (showPrefs) {
                        _finish(openPreferences: true);
                      } else if (last) {
                        _finish();
                      } else {
                        _page.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(showPrefs
                        ? 'Set my preferences'
                        : last
                            ? 'Get started'
                            : 'Next'),
                  ),
                  if (showPrefs)
                    TextButton(
                      key: const Key('onboarding-later'),
                      onPressed: _finish,
                      child: const Text('Maybe later'),
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

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity)),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 64, color: AppColors.accent),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      ),
    ),
    );
  }
}
