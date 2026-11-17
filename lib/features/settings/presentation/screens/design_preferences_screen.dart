import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../auth/data/models/user_preferences.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../widgets/settings_widgets.dart';

class DesignPreferencesScreen extends ConsumerStatefulWidget {
  const DesignPreferencesScreen({super.key});

  @override
  ConsumerState<DesignPreferencesScreen> createState() =>
      _DesignPreferencesScreenState();
}

class _DesignPreferencesScreenState
    extends ConsumerState<DesignPreferencesScreen> {
  late DesignPreferences _prefs;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(currentUserProvider)?.designPreferences ??
        const DesignPreferences();
    _notes = TextEditingController(text: _prefs.notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<String> _toggle(List<String> list, String value) {
    if (list.contains(value)) return [...list]..remove(value);
    if (list.length >= DesignPreferences.maxPerGroup) return list;
    return [...list, value];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(authStateProvider.notifier)
          .saveDesignPreferences(_prefs.copyWith(notes: _notes.text.trim()));
      if (!mounted) return;
      showAppSnackbar(context, 'Design preferences saved');
      leaveSettings(context, ref);
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context,
            userMessage(e, fallback: 'Could not save. Please try again.'),
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _group(String title, List<String> options, List<String> selected,
      void Function(String) onTap) {
    return SettingsCard(
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                FilterChip(
                  label: Text(o),
                  selected: selected.contains(o),
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected.contains(o)
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                  onSelected: (_) => onTap(o),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Design preferences',
      subtitle: 'The design assistant uses these to suggest pieces you like',
      bottom: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          key: const Key('save-preferences'),
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
              : const Text('Save preferences'),
        ),
      ),
      children: [
        _group('Styles you like', DesignPreferences.styleOptions, _prefs.styles,
            (o) => setState(() => _prefs =
                _prefs.copyWith(styles: _toggle(_prefs.styles, o)))),
        _group('Colours', DesignPreferences.colourOptions, _prefs.colours,
            (o) => setState(() => _prefs =
                _prefs.copyWith(colours: _toggle(_prefs.colours, o)))),
        _group('Materials', DesignPreferences.materialOptions, _prefs.materials,
            (o) => setState(() => _prefs =
                _prefs.copyWith(materials: _toggle(_prefs.materials, o)))),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.eco_outlined,
              title: 'Prefer eco-friendly pieces',
              value: _prefs.ecoFriendly,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs.copyWith(ecoFriendly: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                key: const Key('preference-notes'),
                controller: _notes,
                maxLength: DesignPreferences.maxNotes,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'Anything else? (optional)',
                  hintText: 'e.g. small flat, two cats, need lots of storage',
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textHint),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
