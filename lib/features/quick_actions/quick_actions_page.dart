import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';

/// The full app catalogue — search, one-tap shortcuts and every module tile,
/// grouped the same way the web app's 25-module blueprint is. This used to be
/// the Home tab; Home itself is now a day-to-day CRM/HRMS dashboard and links
/// in here for "everything else".
class QuickActionsPage extends StatefulWidget {
  const QuickActionsPage({super.key});

  @override
  State<QuickActionsPage> createState() => _QuickActionsPageState();
}

class _QuickActionsPageState extends State<QuickActionsPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: M.heroBg,
        foregroundColor: Colors.white,
        title: const Text('Quick Links', style: TextStyle(color: Colors.white)),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              onClear: () => setState(() {
                _searchCtrl.clear();
                _query = '';
              }),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ..._moduleGroups(context),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  /// Filters every section's own tiles down to ones matching [_query] by title/subtitle —
  /// a section with zero matches disappears entirely (same as it already does when a company
  /// simply can't see any of its tiles) rather than showing an empty heading.
  List<Widget> _moduleGroups(BuildContext context) {
    final out = <Widget>[];
    var anyMatch = false;
    for (final group in AppModules.groupsWithContent) {
      final mods = _query.isEmpty
          ? AppModules.visibleFor(group)
          : AppModules.visibleFor(group).where((m) {
              return m.title.toLowerCase().contains(_query) ||
                  (m.subtitle?.toLowerCase().contains(_query) ?? false);
            }).toList();
      if (mods.isEmpty) continue;
      anyMatch = true;
      out.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Text(
            group.label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: context.mutedColor,
            ),
          ),
        ),
      ));
      out.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.82,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => _ModuleTile(module: mods[i]),
            childCount: mods.length,
          ),
        ),
      ));
    }
    if (!anyMatch && _query.isNotEmpty) {
      out.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text('No matches for "$_query"',
                style: TextStyle(color: context.mutedColor, fontSize: 13.5)),
          ),
        ),
      ));
    }
    return out;
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.altSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.lineColor),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: context.mutedColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search WA Chat, Leads, HR…',
                  hintStyle: TextStyle(color: context.mutedColor, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : InkWell(
                      onTap: onClear,
                      child: Icon(Icons.close_rounded, color: context.mutedColor, size: 18),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = module.color ?? theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.goToRoute(module.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(module.icon, color: tint, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              module.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}
