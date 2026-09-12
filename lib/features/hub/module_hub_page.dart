import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// Generic landing screen for a module that doesn't yet have a bespoke UI.
/// Lists the module's sub-sections and links back to the web app for the rest.
class ModuleHubPage extends StatelessWidget {
  const ModuleHubPage({super.key, required this.module});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = module.color ?? theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(module.icon, color: tint, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(module.title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (module.subtitle != null)
                      Text(module.subtitle!,
                          style: TextStyle(color: context.mutedColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (module.subSections.isNotEmpty) ...[
            Text('Sections',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...module.subSections.map(
              (s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(s.icon ?? Icons.chevron_right_rounded),
                  title: Text(s.title),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(s.route),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.altSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.lineColor),
            ),
            child: Row(
              children: [
                Icon(Icons.build_circle_outlined, color: context.mutedColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The full ${module.title} workspace is being brought to '
                    'mobile. Core actions are available here — everything else '
                    'lives in the web app for now.',
                    style: TextStyle(
                        color: context.mutedColor, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
