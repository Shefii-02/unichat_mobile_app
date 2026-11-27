import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/features/settings/presentation/pages/settings_page.dart';
import 'package:unichat_mobile_app/features/sticky/sticky_overlay.dart';

/// Profile → Display: everything about how the app looks and what floats over it. All of it is per device.
class DisplayPage extends StatelessWidget {
  const DisplayPage({super.key});

  Widget _section(String title, List<Widget> tiles) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
          ),
          ...tiles,
          const Divider(height: 1),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display')),
      body: ListView(children: [
        _section('Appearance', const [ThemeTile(), EdgeToEdgeTile()]),
        _section('Floating buttons', const [_NotesTile(), _TodoTile()]),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('These settings apply to this phone only.', style: TextStyle(fontSize: 11.5, color: AppColors.textLight)),
        ),
      ]),
    );
  }
}

/// The floating sticky-notes circle — on or off by itself.
class _NotesTile extends ConsumerWidget {
  const _NotesTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        secondary: const Icon(Icons.sticky_note_2_outlined, color: AppColors.textSecondary, size: 22),
        title: const Text('Sticky notes', style: TextStyle(fontSize: 14)),
        subtitle: const Text('Show the floating sticky-notes button.', style: TextStyle(fontSize: 11.5, color: AppColors.textLight)),
        value: ref.watch(stickyNotesEnabledProvider),
        activeThumbColor: AppColors.primary,
        onChanged: (v) => ref.read(stickyNotesEnabledProvider.notifier).set(v),
      );
}

/// The floating to-do circle — on or off by itself.
class _TodoTile extends ConsumerWidget {
  const _TodoTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        secondary: const Icon(Icons.checklist_rounded, color: AppColors.textSecondary, size: 22),
        title: const Text('To-do list', style: TextStyle(fontSize: 14)),
        subtitle: const Text('Show the floating to-do button.', style: TextStyle(fontSize: 11.5, color: AppColors.textLight)),
        value: ref.watch(stickyTodoEnabledProvider),
        activeThumbColor: AppColors.primary,
        onChanged: (v) => ref.read(stickyTodoEnabledProvider.notifier).set(v),
      );
}
