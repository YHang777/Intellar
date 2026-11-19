import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../models/room_design.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/two_factor_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/customer/ar/presentation/screens/ar_previews_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/screens/accessibility_settings_screen.dart';
import '../../features/settings/presentation/screens/design_preferences_screen.dart';
import '../../features/settings/presentation/screens/notification_privacy_screen.dart';
import '../../features/settings/presentation/screens/security_settings_screen.dart';
import '../../features/customer/budget/presentation/screens/budget_planner_screen.dart';
import '../../features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import '../../features/customer/homeowner/presentation/screens/dashboard_screen.dart';
import '../../features/customer/homeowner/presentation/screens/design_report_screen.dart';
import '../../features/customer/homeowner/presentation/screens/homeowner_shell.dart';
import '../../features/customer/homeowner/presentation/screens/profile_screen.dart';
import '../../features/customer/homeowner/presentation/screens/saved_designs_screen.dart';

import '../../features/supplier/presentation/screens/analytics_screen.dart';
import '../../features/supplier/presentation/screens/order_management_screen.dart';
import '../../features/supplier/presentation/screens/product_form_screen.dart';
import '../../features/supplier/presentation/screens/product_management_screen.dart';
import '../../features/supplier/presentation/screens/quote_request_detail_screen.dart';
import '../../features/supplier/presentation/screens/quote_requests_screen.dart';
import '../../features/supplier/presentation/screens/sales_report_screen.dart';
import '../../features/supplier/presentation/screens/supplier_dashboard_screen.dart';
import '../../features/supplier/presentation/screens/supplier_profile_screen.dart';
import '../../features/supplier/presentation/screens/bulk_upload_screen.dart';
import '../../features/supplier/presentation/screens/store_profile_screen.dart';
import '../../features/supplier/presentation/screens/supplier_shell.dart';
import '../../features/supplier/presentation/screens/verification_application_screen.dart';

import '../../features/customer/marketplace/presentation/screens/marketplace_screen.dart';
import '../../features/customer/marketplace/presentation/screens/product_detail_screen.dart';
import '../../features/customer/marketplace/presentation/screens/cart_screen.dart';
import '../../features/customer/marketplace/presentation/screens/checkout_screen.dart';
import '../../features/customer/marketplace/presentation/screens/order_confirmation_screen.dart';
import '../../features/customer/marketplace/presentation/screens/order_history_screen.dart';
import '../../features/customer/marketplace/presentation/screens/buyer_order_detail_screen.dart';
import '../../features/customer/marketplace/presentation/screens/wishlist_screen.dart';
import '../../features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import '../../features/customer/scanner/presentation/screens/shared_design_screen.dart';
import '../../shared/screens/account_required_screen.dart';
import '../../features/customer/ar/data/furniture_model_library.dart';
import '../../features/customer/ar/presentation/ar_viewer_args.dart';
import '../../features/customer/ar/presentation/screens/ar_viewer_screen.dart';
import '../../features/customer/walkthrough/presentation/walkthrough_screen.dart';
import '../../features/supplier/presentation/screens/order_detail_screen.dart';
import '../../shared/screens/order_invoice_screen.dart';
import '../../shared/screens/order_receipt_screen.dart';

import 'route_names.dart';

// Debug-only device sandbox: `flutter run --dart-define=SANDBOX_ROUTE=/walkthrough`
// (or /design-editor, /ar-viewer) opens straight onto that screen with no
// sign-in, for emulator/device testing of the 3D and AR surfaces.
// kDebugMode is a compile-time false in profile/release, so this can never
// ship.
const _sandboxRoute =
    kDebugMode ? String.fromEnvironment('SANDBOX_ROUTE') : '';
const _sandboxRoutes = {'/walkthrough', '/design-editor', '/ar-viewer'};
const _sandbox = _sandboxRoute != '';

const _guestBlockedPrefixes = [
  '/marketplace/cart',
  '/marketplace/checkout',
  '/marketplace/order-confirmation',
  '/marketplace/orders',
  '/marketplace/wishlist',
  '/budget',
  '/settings/security',
  '/settings/notifications',
  '/settings/preferences',
  '/orders/',
  '/design/report',
  '/supplier',
  '/store-profile',
];

bool _guestBlocked(String loc) => _guestBlockedPrefixes.any(loc.startsWith);

// A share link opened while signed out survives the trip through sign-in.
String? _pendingSharedLink;

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefresh = ref.watch(authRefreshProvider);

  return GuardedGoRouter(
    initialLocation: _sandbox ? _sandboxRoute : '/login',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      if (_sandbox && _sandboxRoutes.contains(state.matchedLocation)) {
        return null;
      }
      final authState = ref.read(authStateProvider);

      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final user = authState.whenOrNull(data: (u) => u);
      final isLoggedIn = user != null;
      final isOnAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/verify-email';

      if (!isLoggedIn && !isOnAuthRoute) {
        if (state.matchedLocation.startsWith('/d/')) {
          _pendingSharedLink = state.matchedLocation;
        }
        return '/login';
      }
      final home =
          (user?.isHomeowner ?? true) ? '/home' : '/supplier/dashboard';
      final loc = state.matchedLocation;
      String? takePendingLink() {
        final p = _pendingSharedLink;
        if (p == null || user == null || !user.isHomeowner ||
            !user.onboardingCompleted) {
          return null;
        }
        _pendingSharedLink = null;
        return p;
      }
      // Guests explore freely but anything tied to an account needs sign-up.
      if (isLoggedIn && user.isGuest && _guestBlocked(loc)) {
        return '/account-required';
      }
      if (isLoggedIn && user.twoFactorPending) {
        return loc == '/two-factor' ? null : '/two-factor';
      }
      if (loc == '/two-factor') {
        return isLoggedIn ? (takePendingLink() ?? home) : '/login';
      }
      if (isLoggedIn && !user.onboardingCompleted) {
        return loc == '/onboarding' ? null : '/onboarding';
      }
      // A guest may open sign-in / sign-up on top of what they were doing
      // and come straight back with Back if they change their mind.
      if (isLoggedIn && isOnAuthRoute && !user.isGuest) {
        return takePendingLink() ?? home;
      }
      // Supplier-only, but outside /supplier/ (so the supplier rule below
      // would otherwise bounce it to the dashboard).
      if (loc == '/store-profile') {
        return (isLoggedIn && user.isSupplier) ? null : home;
      }
      if (loc == '/onboarding' ||
          loc == '/notifications' ||
          loc == '/ar-previews' ||
          loc.startsWith('/settings/')) {
        if (isLoggedIn && user.isSupplier && loc == '/settings/preferences') {
          return '/supplier/dashboard';
        }
        return null;
      }
      if (isLoggedIn && user.isHomeowner &&
          state.matchedLocation.startsWith('/supplier')) {
        return '/home';
      }
      final isStorefrontBrowse =
          state.matchedLocation == '/marketplace' ||
              state.matchedLocation.startsWith('/marketplace/product/') ||
              state.matchedLocation == '/ar-viewer';
      final isSharedInvoice =
          state.matchedLocation.startsWith('/orders/');
      if (isLoggedIn && user.isSupplier &&
          !isStorefrontBrowse &&
          !isSharedInvoice &&
          !state.matchedLocation.startsWith('/supplier') &&
          !isOnAuthRoute) {
        return '/supplier/dashboard';
      }
      return null;
    },
    routes: [
      // ── Auth routes (no shell) ──
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        pageBuilder: (_, __) => _buildPage(const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        name: RouteNames.register,
        pageBuilder: (_, __) => _buildPage(const RegisterScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        name: RouteNames.forgotPassword,
        pageBuilder: (_, __) => _buildPage(const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        name: RouteNames.verifyEmail,
        pageBuilder: (_, __) => _buildPage(const VerifyEmailScreen()),
      ),

      GoRoute(
        path: '/two-factor',
        name: RouteNames.twoFactor,
        pageBuilder: (_, __) => _buildPage(const TwoFactorScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        name: RouteNames.onboarding,
        pageBuilder: (_, __) => _buildPage(const OnboardingScreen()),
      ),

      GoRoute(
        path: '/ar-previews',
        name: RouteNames.arPreviews,
        pageBuilder: (_, __) => _buildPage(const ArPreviewsScreen()),
      ),

      GoRoute(
        path: '/supplier/products/bulk-upload',
        name: RouteNames.supplierBulkUpload,
        pageBuilder: (_, __) => _buildPage(const BulkUploadScreen()),
      ),

      GoRoute(
        path: '/store-profile',
        name: RouteNames.storeProfile,
        pageBuilder: (_, __) => _buildPage(const StoreProfileScreen()),
      ),

      GoRoute(
        path: '/notifications',
        name: RouteNames.notifications,
        pageBuilder: (_, __) => _buildPage(const NotificationsScreen()),
      ),

      // ── Settings (both roles) ──
      GoRoute(
        path: '/settings/security',
        name: RouteNames.settingsSecurity,
        pageBuilder: (_, __) => _buildPage(const SecuritySettingsScreen()),
      ),
      GoRoute(
        path: '/settings/notifications',
        name: RouteNames.settingsNotifications,
        pageBuilder: (_, __) => _buildPage(const NotificationPrivacyScreen()),
      ),
      GoRoute(
        path: '/settings/accessibility',
        name: RouteNames.settingsAccessibility,
        pageBuilder: (_, __) =>
            _buildPage(const AccessibilitySettingsScreen()),
      ),
      GoRoute(
        path: '/settings/preferences',
        name: RouteNames.settingsPreferences,
        pageBuilder: (_, __) => _buildPage(const DesignPreferencesScreen()),
      ),

      // ── Standalone routes ──
      GoRoute(
        path: '/budget',
        name: RouteNames.homeownerBudget,
        pageBuilder: (_, __) => _buildPage(const BudgetPlannerScreen()),
      ),

      // ── Design Editor (full-screen from scan or saved designs) ──
      GoRoute(
        path: '/design-editor',
        name: RouteNames.homeownerDesignEditor,
        pageBuilder: (_, state) => _buildPage(
          RoomScannerScreen(existingDesign: state.extra as dynamic),
        ),
      ),

      GoRoute(
        path: '/account-required',
        pageBuilder: (_, __) => _buildPage(const AccountRequiredScreen()),
      ),

      // ── Shared design link (/d/<token>) → opens in the 3D planner ──
      GoRoute(
        path: '/d/:token',
        pageBuilder: (_, state) => _buildPage(
          SharedDesignScreen(token: state.pathParameters['token'] ?? ''),
        ),
      ),

      // ── Walkthrough (2D walk of a plan; extra: RoomDesign?) ──
      GoRoute(
        path: '/walkthrough',
        name: RouteNames.homeownerWalkthrough,
        pageBuilder: (_, state) => _buildPage(
          WalkthroughScreen(design: state.extra as RoomDesign?),
        ),
      ),

      // ── AR Viewer (full-screen; extras: Product | ArViewerArgs |
      // List<ArFurnitureItem>) ──
      GoRoute(
        path: '/ar-viewer',
        name: RouteNames.arViewer,
        pageBuilder: (_, state) => _buildPage(_buildArViewer(state.extra)),
      ),

      // ── Marketplace (buyer, full-screen over shell) ──
      GoRoute(
        path: '/marketplace/product/:id',
        name: RouteNames.homeownerProductDetail,
        pageBuilder: (_, state) => _buildPage(
          ProductDetailScreen(
            productId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/marketplace/cart',
        name: RouteNames.homeownerCart,
        pageBuilder: (_, __) => _buildPage(const CartScreen()),
      ),
      GoRoute(
        path: '/marketplace/checkout',
        name: RouteNames.homeownerCheckout,
        pageBuilder: (_, __) => _buildPage(const CheckoutScreen()),
      ),
      GoRoute(
        path: '/marketplace/order-confirmation',
        name: RouteNames.homeownerOrderConfirmation,
        pageBuilder: (_, __) =>
            _buildPage(const OrderConfirmationScreen()),
      ),
      GoRoute(
        path: '/marketplace/orders',
        name: RouteNames.homeownerOrderHistory,
        pageBuilder: (_, state) => _buildPage(OrderHistoryScreen(
            openQuotes: state.uri.queryParameters['tab'] == 'quotes')),
      ),
      GoRoute(
        path: '/marketplace/orders/:id',
        name: RouteNames.homeownerOrderDetail,
        pageBuilder: (_, state) => _buildPage(
          BuyerOrderDetailScreen(
            orderId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/marketplace/wishlist',
        name: RouteNames.homeownerWishlist,
        pageBuilder: (_, __) => _buildPage(const WishlistScreen()),
      ),

      // ── Supplier product form (create / edit, full-screen) ──
      GoRoute(
        path: '/supplier/products/new',
        name: RouteNames.supplierProductNew,
        pageBuilder: (_, __) => _buildPage(const ProductFormScreen()),
      ),
      GoRoute(
        path: '/supplier/products/:id/edit',
        name: RouteNames.supplierProductEdit,
        pageBuilder: (_, state) => _buildPage(
          ProductFormScreen(productId: state.pathParameters['id']),
        ),
      ),

      // ── Supplier order detail (full-screen) ──
      GoRoute(
        path: '/supplier/orders/:id',
        name: RouteNames.supplierOrderDetail,
        pageBuilder: (_, state) => _buildPage(
          SupplierOrderDetailScreen(
            orderId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Supplier quote requests (bulk-quote inbox, full-screen) ──
      GoRoute(
        path: '/supplier/quotes',
        name: RouteNames.supplierQuoteRequests,
        pageBuilder: (_, __) => _buildPage(const QuoteRequestsScreen()),
      ),
      GoRoute(
        path: '/supplier/quotes/:id',
        name: RouteNames.supplierQuoteRequestDetail,
        pageBuilder: (_, state) => _buildPage(
          QuoteRequestDetailScreen(
            requestId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Supplier verification application (full-screen) ──
      GoRoute(
        path: '/supplier/verification',
        name: RouteNames.supplierVerification,
        pageBuilder: (_, __) =>
            _buildPage(const VerificationApplicationScreen()),
      ),

      // ── Supplier sales report (full-screen) ──
      GoRoute(
        path: '/supplier/sales-report',
        name: RouteNames.supplierSalesReport,
        pageBuilder: (_, __) => _buildPage(const SalesReportScreen()),
      ),

      // ── Invoice (shared: buyer receipt + seller paperwork, full-screen) ──
      GoRoute(
        path: '/orders/:orderId/invoice/:supplierId',
        name: RouteNames.orderInvoice,
        pageBuilder: (_, state) => _buildPage(
          OrderInvoiceScreen(
            orderId: state.pathParameters['orderId']!,
            supplierId: state.pathParameters['supplierId']!,
          ),
        ),
      ),

      // ── Payment receipt (buyer, full-screen) ──
      GoRoute(
        path: '/orders/:orderId/receipt',
        name: RouteNames.orderReceipt,
        pageBuilder: (_, state) => _buildPage(
          OrderReceiptScreen(orderId: state.pathParameters['orderId']!),
        ),
      ),

      // ── Customer design report (full-screen) ──
      GoRoute(
        path: '/design/report',
        name: RouteNames.designReport,
        pageBuilder: (_, __) => _buildPage(const DesignReportScreen()),
      ),

      // ── Homeowner shell ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            HomeownerShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: RouteNames.homeownerDashboard,
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/design',
                name: RouteNames.homeownerScan,
                builder: (_, __) => const RoomScannerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai',
                name: RouteNames.homeownerAi,
                builder: (_, __) => const AiRecommendationScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/marketplace',
                name: RouteNames.homeownerMarketplace,
                builder: (_, __) => const MarketplaceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/saved',
                name: RouteNames.homeownerSaved,
                builder: (_, __) => const SavedDesignsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: RouteNames.homeownerProfile,
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Supplier shell ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            SupplierShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/dashboard',
                name: RouteNames.supplierDashboard,
                builder: (_, __) => const SupplierDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/products',
                name: RouteNames.supplierProducts,
                builder: (_, __) => const ProductManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/orders',
                name: RouteNames.supplierOrders,
                builder: (_, __) => const OrderManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/analytics',
                name: RouteNames.supplierAnalytics,
                builder: (_, __) => const SalesAnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/profile',
                name: RouteNames.supplierProfile,
                builder: (_, __) => const SupplierProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class GuardedGoRouter extends GoRouter {
  GuardedGoRouter({
    required List<RouteBase> routes,
    GoRouterRedirect? redirect,
    super.refreshListenable,
    super.initialLocation,
  }) : super.routingConfig(
          routingConfig: ValueNotifier<RoutingConfig>(
            RoutingConfig(
              routes: routes,
              redirect: redirect ?? (_, __) => null,
            ),
          ),
        );

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    if (_wouldStackSecondShell(location, extra) ||
        _wouldSwitchShellBranch(location, extra)) {
      go(location, extra: extra);
      return Future<T?>.value();
    }
    return super.push<T>(location, extra: extra);
  }

  bool _wouldStackSecondShell(String location, Object? extra) {
    final RouteMatchList current = routerDelegate.currentConfiguration;
    if (current.matches.isEmpty ||
        current.matches.last is! ImperativeRouteMatch) {
      return false;
    }
    final RouteMatchList next =
        configuration.findMatch(Uri.parse(location), extra: extra);
    return next.matches.any((RouteMatchBase match) => match is ShellRouteMatch);
  }

  bool _wouldSwitchShellBranch(String location, Object? extra) {
    final RouteMatchList current = routerDelegate.currentConfiguration;
    if (current.matches.isEmpty) return false;
    final RouteMatchBase top = current.matches.last;
    if (top is! ShellRouteMatch) return false;
    final RouteMatchList next =
        configuration.findMatch(Uri.parse(location), extra: extra);
    if (next.matches.isEmpty) return false;
    final RouteMatchBase nextTop = next.matches.last;
    if (nextTop is! ShellRouteMatch) return false;
    if (!identical(nextTop.route, top.route)) return false;
    return nextTop.navigatorKey != top.navigatorKey;
  }
}

CustomTransitionPage<T> _buildPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

Widget _buildArViewer(Object? extra) {
  if (extra is Product) return ArViewerScreen(product: extra);
  if (extra is ArViewerArgs) {
    return ArViewerScreen(
      items: extra.items,
      design: extra.design,
      title: extra.title ?? 'AR Preview',
    );
  }
  if (extra is List<ArFurnitureItem>) return ArViewerScreen(items: extra);
  return const ArViewerScreen();
}
