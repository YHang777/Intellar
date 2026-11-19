import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../widgets/float_button.dart';
import '../widgets/guest_gate.dart';

// Where a guest lands if they open a page that needs an account (cart,
// orders, budget, account settings...).
class AccountRequiredScreen extends StatelessWidget {
  const AccountRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(8, 60, 8, 24),
                child: GuestSignUpSheet(action: 'use this part of Intellar'),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
    );
  }
}
