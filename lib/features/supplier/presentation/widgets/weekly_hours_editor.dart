import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/weekly_hours.dart';
import '../../../../shared/widgets/app_feedback.dart';

// Day-by-day opening hours: a switch per day and tap-to-pick times. Closing
// times earlier than opening are refused at the picker, so a saved schedule
// is always one buyers can read.
class WeeklyHoursEditor extends StatelessWidget {
  const WeeklyHoursEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final WeeklyHours value;
  final ValueChanged<WeeklyHours> onChanged;

  static const _defaultDay = DayHours(9 * 60, 18 * 60);

  Future<void> _pick(
    BuildContext context,
    int weekday,
    DayHours current, {
    required bool opening,
  }) async {
    final minutes = opening ? current.openMinutes : current.closeMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
      helpText: opening ? 'Opens at' : 'Closes at',
    );
    if (picked == null || !context.mounted) return;
    final m = picked.hour * 60 + picked.minute;
    final next = opening
        ? DayHours(m, current.closeMinutes)
        : DayHours(current.openMinutes, m);
    if (!next.isValid) {
      showAppSnackbar(context, 'Closing time must be after opening time.',
          isError: true);
      return;
    }
    onChanged(value.withDay(weekday, next));
  }

  @override
  Widget build(BuildContext context) {
    final monday = value.days[1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Turn on the days you are open, or start from typical hours.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        for (var d = 1; d <= 7; d++) _dayRow(context, d),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (value.isEmpty)
              TextButton.icon(
                key: const Key('hours-typical'),
                onPressed: () => onChanged(WeeklyHours.typical),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Use typical hours'),
              ),
            if (monday != null)
              TextButton.icon(
                key: const Key('hours-copy-monday'),
                onPressed: () {
                  var next = value;
                  for (var d = 2; d <= 5; d++) {
                    next = next.withDay(d, monday);
                  }
                  onChanged(next);
                },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy Monday to weekdays'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _dayRow(BuildContext context, int weekday) {
    final hours = value.days[weekday];
    final label = WeeklyHours.dayShort[weekday - 1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Switch(
            key: Key('hours-open-$weekday'),
            value: hours != null,
            activeTrackColor: AppColors.accent,
            onChanged: (open) => onChanged(
                value.withDay(weekday, open ? (hours ?? _defaultDay) : null)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hours == null
                ? Text('Closed',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textHint))
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      _timeButton(
                        context,
                        key: Key('hours-from-$weekday'),
                        minutes: hours.openMinutes,
                        onTap: () =>
                            _pick(context, weekday, hours, opening: true),
                      ),
                      Text('–',
                          style: TextStyle(color: AppColors.textSecondary)),
                      _timeButton(
                        context,
                        key: Key('hours-to-$weekday'),
                        minutes: hours.closeMinutes,
                        onTap: () =>
                            _pick(context, weekday, hours, opening: false),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timeButton(
    BuildContext context, {
    required Key key,
    required int minutes,
    required VoidCallback onTap,
  }) =>
      OutlinedButton(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: GoogleFonts.poppins(fontSize: 13),
        ),
        child: Text(WeeklyHours.formatTime(minutes)),
      );
}
