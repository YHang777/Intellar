import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

// The app's type scale: seven sizes, all Poppins. Screens pick a step from
// here (or the matching textTheme slot) instead of inventing a size, so the
// same kind of text looks the same on every page. Letter-spacing is ~0:
// Material's default wide tracking on Poppins reads oversized and dated.
abstract final class AppType {
  static const double display = 22; // page titles
  static const double title = 18; // sheet / dialog / section titles
  static const double subtitle = 16; // card titles, primary buttons
  static const double body = 14; // body text, list rows
  static const double secondary = 13; // supporting lines, small buttons
  static const double caption = 12; // captions, meta
  static const double tiny = 11; // badges, chips' fine print

  /// Every size the app uses, smallest first.
  static const List<double> scale = [
    tiny,
    caption,
    secondary,
    body,
    subtitle,
    title,
    display,
  ];

  static TextTheme textTheme() {
    TextStyle s(double size, FontWeight weight, {double tracking = 0}) =>
        GoogleFonts.poppins(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: tracking,
          color: AppColors.textPrimary,
        );
    return TextTheme(
      displayLarge: s(display, FontWeight.w700, tracking: -0.3),
      displayMedium: s(display, FontWeight.w700, tracking: -0.3),
      displaySmall: s(display, FontWeight.w700, tracking: -0.3),
      headlineLarge: s(display, FontWeight.w700, tracking: -0.3),
      headlineMedium: s(display, FontWeight.w700, tracking: -0.3),
      headlineSmall: s(title, FontWeight.w700, tracking: -0.2),
      titleLarge: s(title, FontWeight.w600, tracking: -0.2),
      titleMedium: s(subtitle, FontWeight.w600),
      titleSmall: s(body, FontWeight.w600),
      // ListTile titles use bodyLarge and subtitles bodyMedium in Material 3,
      // which is why list rows were reading at 16 with wide tracking.
      bodyLarge: s(body, FontWeight.w400),
      bodyMedium: s(secondary, FontWeight.w400),
      bodySmall: s(caption, FontWeight.w400),
      labelLarge: s(body, FontWeight.w600),
      labelMedium: s(caption, FontWeight.w500),
      labelSmall: s(tiny, FontWeight.w500),
    );
  }

  /// The scale step a hand-picked size belongs to (used when migrating).
  static double snap(double size) {
    if (size <= 10.5) return tiny;
    if (size <= 11) return tiny;
    if (size <= 12) return caption;
    if (size <= 13) return secondary;
    if (size <= 14) return body;
    if (size <= 16) return subtitle;
    if (size <= 18) return title;
    return display;
  }
}
