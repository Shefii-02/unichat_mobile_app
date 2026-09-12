import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/widgets/data_widgets.dart';

export 'package:unichat_mobile_app/core/widgets/data_widgets.dart';
export 'package:unichat_mobile_app/core/widgets/form_kit.dart';
export 'package:unichat_mobile_app/core/theme/app_theme.dart';
export 'package:unichat_mobile_app/core/network/api.dart' show apiErrorMessage, Api;

/// A record row from the API.
typedef Rec = Map<String, dynamic>;

/// A list bound to a [FutureProvider] returning rows, with pull-to-refresh,
/// loading / error / empty handling, and an optional pinned header.
class ProviderList extends ConsumerWidget {
  const ProviderList({
    super.key,
    required this.provider,
    required this.tile,
    this.header,
    this.emptyLabel = 'Nothing here yet',
    this.emptyIcon = Icons.inbox_rounded,
    this.padding = const EdgeInsets.all(16),
  });

  final FutureProvider<List<Rec>> provider;
  final Widget Function(BuildContext, Rec) tile;
  final Widget? header;
  final String emptyLabel;
  final IconData emptyIcon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return AsyncView<List<Rec>>(
      value: async,
      onRefresh: () async => ref.invalidate(provider),
      isEmpty: (d) => d.isEmpty && header == null,
      emptyLabel: emptyLabel,
      emptyIcon: emptyIcon,
      data: (rows) => ListView.separated(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length + (header != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          if (header != null && i == 0) return header!;
          final row = rows[i - (header != null ? 1 : 0)];
          return tile(ctx, row);
        },
      ),
    );
  }
}

/// An object bound to a [FutureProvider] returning one map.
class ProviderObject extends ConsumerWidget {
  const ProviderObject({
    super.key,
    required this.provider,
    required this.builder,
    this.padding = const EdgeInsets.all(16),
  });

  final FutureProvider<Rec> provider;
  final Widget Function(BuildContext, Rec) builder;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return AsyncView<Rec>(
      value: async,
      onRefresh: () async => ref.invalidate(provider),
      data: (row) => SingleChildScrollView(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        child: builder(context, row),
      ),
    );
  }
}

/// Standard card wrapper for a record row.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.onTap,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = leadingColor ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (leadingIcon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(leadingIcon, size: 20, color: c),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!,
                              style: TextStyle(
                                  color: context.mutedColor, fontSize: 12.5),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              if (footer != null) ...[
                const SizedBox(height: 10),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid of [StatTile]s from a list of (label, value, icon) tuples.
class StatGrid extends StatelessWidget {
  const StatGrid(this.items, {super.key, this.crossAxisCount = 2});
  final List<(String, String, IconData)> items;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: items
          .map((t) => StatTile(label: t.$1, value: t.$2, icon: t.$3))
          .toList(),
    );
  }
}

// ── formatting helpers ────────────────────────────────────────────────
String str(Object? v, [String fallback = '—']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String money(Object? v, {String symbol = '₹'}) {
  final n = num.tryParse('${v ?? ''}') ?? 0;
  return '$symbol${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2)}';
}

String compact(Object? v) {
  final n = num.tryParse('${v ?? ''}') ?? 0;
  if (n >= 1e7) return '${(n / 1e7).toStringAsFixed(1)}Cr';
  if (n >= 1e5) return '${(n / 1e5).toStringAsFixed(1)}L';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}

String when(Object? v) {
  if (v == null) return '—';
  final d = DateTime.tryParse(v.toString());
  if (d == null) return v.toString();
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${d.day}/${d.month}/${d.year}';
}

/// A trailing overflow menu for a record card — edit / toggle / delete etc.
class RowMenu extends StatelessWidget {
  const RowMenu({super.key, required this.items});

  /// Each entry: (label, icon, callback). A null entry renders a divider.
  final List<(String, IconData, VoidCallback)?> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.whereType<(String, IconData, VoidCallback)>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (i) => visible[i].$3(),
      itemBuilder: (_) => [
        for (var i = 0; i < visible.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                Icon(visible[i].$2,
                    size: 18,
                    color: visible[i].$1.toLowerCase().contains('delete')
                        ? AppPalette.danger
                        : null),
                const SizedBox(width: 10),
                Text(visible[i].$1),
              ],
            ),
          ),
      ],
    );
  }
}

/// Runs an async action with a snackbar on error / success and returns success.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    return false;
  }
}
