import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/room_design.dart';
import '../../data/design_share.dart';

// Opened from a share link (https://…/d/<token> or intellar://open/d/<token>):
// loads the plan and hands it to the 3D planner as an unsaved copy.
class SharedDesignScreen extends StatefulWidget {
  const SharedDesignScreen({super.key, required this.token, this.client});

  final String token;
  final DesignShareClient? client;

  @override
  State<SharedDesignScreen> createState() => _SharedDesignScreenState();
}

class _SharedDesignScreenState extends State<SharedDesignScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final RoomDesign? design =
          await (widget.client ?? DesignShareClient()).open(widget.token);
      if (!mounted) return;
      if (design == null) {
        setState(() => _error = 'This shared design was not found.');
        return;
      }
      context.replace('/design-editor', extra: design);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessage(e,
          fallback: 'Could not open the shared design. Please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared design')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Opening the room…',
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off, size: 40, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(_error!,
                        key: const Key('shared-design-error'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/home'),
                          child: const Text('Go home'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
