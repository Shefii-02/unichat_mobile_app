import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// Renders an [AsyncValue] with consistent loading / error / empty states and a
/// pull-to-refresh wrapper.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onRefresh,
    required this.data,
    this.isEmpty,
    this.emptyLabel = 'Nothing here yet',
    this.emptyIcon = Icons.inbox_rounded,
  });

  final AsyncValue<T> value;
  final Future<void> Function() onRefresh;
  final Widget Function(T data) data;
  final bool Function(T data)? isEmpty;
  final String emptyLabel;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: value.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrorState(message: '$e', onRetry: onRefresh),
        data: (d) {
          if (isEmpty?.call(d) ?? false) {
            return _EmptyState(label: emptyLabel, icon: emptyIcon);
          }
          return data(d);
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => ListView(
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 140),
          Icon(icon, size: 56, color: context.mutedColor),
          const SizedBox(height: 12),
          Center(
            child: Text(label, style: TextStyle(color: context.mutedColor)),
          ),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.error_outline_rounded, size: 48, color: AppPalette.danger),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedColor)),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
}

/// Compact metric card used on dashboards.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tint,
    this.delta,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tint;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = tint ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: c),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: context.mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (delta != null) ...[
            const SizedBox(height: 2),
            Text(delta!, style: TextStyle(color: c, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

/// A key/value row for detail screens.
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: context.mutedColor)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: valueColor)),
          ),
        ],
      ),
    );
  }
}

/// Small coloured status pill.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? _autoColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: c, fontSize: 11, fontWeight: FontWeight.w700, height: 1.2),
      ),
    );
  }

  static Color _autoColor(String s) {
    final v = s.toLowerCase();
    if (['active', 'live', 'running', 'approved', 'connected', 'sent',
            'completed', 'delivered', 'success', 'paid', 'working']
        .any(v.contains)) {
      return AppPalette.success;
    }
    if (['pending', 'paused', 'draft', 'in_review', 'review', 'scheduled',
            'processing', 'syncing']
        .any(v.contains)) {
      return AppPalette.warning;
    }
    if (['failed', 'error', 'rejected', 'disconnected', 'stopped', 'expired',
            'cancelled', 'lost', 'inactive']
        .any(v.contains)) {
      return AppPalette.danger;
    }
    return AppPalette.info;
  }
}

/// Section header with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
