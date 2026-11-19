import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/guest_gate.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/user_errors.dart';
import '../../../../models/room_design.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../data/design_share.dart';

bool _sharing = false;

Future<void> shareDesignLink(BuildContext context, WidgetRef ref, RoomDesign design,
    {DesignShareClient? client}) async {
  if (!await requireAccount(context, ref, 'share your design as a link')) return;
  if (!context.mounted) return;
  if (_sharing) return;
  _sharing = true;
  showAppSnackbar(context, 'Creating a share link…');
  try {
    final url = await (client ?? DesignShareClient()).createLink(design);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      text: 'Take a look around my room design in 3D: $url',
      subject: design.name.trim().isEmpty ? 'My room design' : design.name,
    ));
  } catch (e) {
    if (context.mounted) {
      showAppSnackbar(
          context,
          userMessage(e,
              fallback: 'Could not create a share link. Please try again.'),
          isError: true);
    }
  } finally {
    _sharing = false;
  }
}
