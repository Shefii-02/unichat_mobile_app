import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// Opens a modal form sheet and returns `true` if the save succeeded.
Future<bool> showFormSheet(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext) fields,
  required Future<void> Function() onSubmit,
  String submitLabel = 'Save',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,   // always above the whole app, never inside a tab's nested navigator (which the Home rebuilds under)
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _FormSheet(
      title: title,
      fields: fields,
      onSubmit: onSubmit,
      submitLabel: submitLabel,
    ),
  );
  return result ?? false;
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({
    required this.title,
    required this.fields,
    required this.onSubmit,
    required this.submitLabel,
  });

  final String title;
  final List<Widget> Function(BuildContext) fields;
  final Future<void> Function() onSubmit;
  final String submitLabel;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState?.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: context.lineColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      ...widget.fields(context),
                    ],
                  ),
                ),
              ),
              // the problem is shown right above the button, so it is never hidden below a long form or behind the keyboard
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppPalette.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!, style: const TextStyle(color: AppPalette.danger, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(widget.submitLabel),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Field widgets ─────────────────────────────────────────────────────

class FField extends StatelessWidget {
  const FField({super.key, required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13.5)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!,
                  style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
            ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class FText extends StatelessWidget {
  const FText({
    super.key,
    required this.label,
    required this.onSaved,
    this.initial,
    this.hint,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.obscure = false,
  });

  final String label;
  final void Function(String) onSaved;
  final String? initial;
  final String? hint;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return FField(
      label: label,
      child: TextFormField(
        initialValue: initial,
        maxLines: obscure ? 1 : maxLines,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        onSaved: (v) => onSaved(v?.trim() ?? ''),
      ),
    );
  }
}

class FNumber extends StatelessWidget {
  const FNumber({
    super.key,
    required this.label,
    required this.onSaved,
    this.initial,
    this.required = false,
  });
  final String label;
  final void Function(num?) onSaved;
  final num? initial;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return FField(
      label: label,
      child: TextFormField(
        initialValue: initial?.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        onSaved: (v) =>
            onSaved(v == null || v.trim().isEmpty ? null : num.tryParse(v.trim())),
      ),
    );
  }
}

/// A short list of choices shown as round radio buttons (every option visible) instead of a dropdown.
class FRadio<T> extends StatefulWidget {
  const FRadio({super.key, required this.label, required this.options, required this.onSaved, this.initial, this.labelOf, this.hint, this.horizontal = true});
  final String label;
  final List<T> options;
  final void Function(T?) onSaved;
  final T? initial;
  final String Function(T)? labelOf;
  final String? hint;
  final bool horizontal;   // true = chips in a wrapping row · false = one option per line
  @override
  State<FRadio<T>> createState() => _FRadioState<T>();
}

class _FRadioState<T> extends State<FRadio<T>> {
  late T? _value = widget.initial;
  String _label(T o) {
    if (widget.labelOf != null) return widget.labelOf!(o);
    final s = '$o';
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget option(T o) {
      final on = o == _value;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _value = o),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(mainAxisSize: widget.horizontal ? MainAxisSize.min : MainAxisSize.max, children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: on ? primary : context.mutedColor),
            const SizedBox(width: 6),
            Flexible(child: Text(_label(o), style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
          ]),
        ),
      );
    }

    return FField(
      label: widget.label,
      hint: widget.hint,
      child: FormField<T>(
        initialValue: _value,
        onSaved: (_) => widget.onSaved(_value),
        builder: (_) => widget.horizontal
            ? Wrap(spacing: 8, children: [for (final o in widget.options) option(o)])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final o in widget.options) option(o)]),
      ),
    );
  }
}

class FSelect<T> extends StatefulWidget {
  const FSelect({
    super.key,
    required this.label,
    required this.options,
    required this.onSaved,
    this.initial,
    this.labelOf,
    this.hint,
  });

  final String label;
  final List<T> options;
  final void Function(T?) onSaved;
  final T? initial;
  final String Function(T)? labelOf;
  final String? hint;

  @override
  State<FSelect<T>> createState() => _FSelectState<T>();
}

class _FSelectState<T> extends State<FSelect<T>> {
  late T? _value = widget.initial;

  String _label(T o) => widget.labelOf?.call(o) ?? '$o';

  @override
  Widget build(BuildContext context) {
    // a short list is a plain dropdown; a longer one opens a sheet with a search box, so one entry can be found by typing
    if (widget.options.length > 5) {
      return FField(
        label: widget.label,
        child: FormField<T>(
          initialValue: _value,
          onSaved: (v) => widget.onSaved(v ?? _value),
          builder: (st) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showSearchPicker<T>(context, title: widget.label, options: widget.options, labelOf: _label, selected: _value);
              if (picked != null) {
                setState(() => _value = picked.value);
                st.didChange(picked.value);
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(border: OutlineInputBorder(), suffixIcon: Icon(Icons.search_rounded), isDense: true),
              child: Text(
                _value != null ? _label(_value as T) : (widget.hint ?? 'Search & select'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _value == null ? TextStyle(color: context.mutedColor) : null,
              ),
            ),
          ),
        ),
      );
    }
    return FField(
      label: widget.label,
      child: DropdownButtonFormField<T>(
        initialValue: _value,
        isExpanded: true,
        hint: widget.hint != null ? Text(widget.hint!) : null,
        items: widget.options.map((o) => DropdownMenuItem(value: o, child: Text(_label(o)))).toList(),
        onChanged: (v) => setState(() => _value = v),
        onSaved: (v) => widget.onSaved(v ?? _value),
      ),
    );
  }
}

/// A bottom sheet with a search box over [options]; returns the chosen one (wrapped, so choosing "nothing" can be told from closing).
Future<({T value})?> showSearchPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  String? Function(T)? subtitleOf,
  T? selected,
}) {
  return showModalBottomSheet<({T value})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(builder: (ctx, set) {
        final shown = [for (final o in options) if (q.isEmpty || labelOf(o).toLowerCase().contains(q) || (subtitleOf?.call(o) ?? '').toLowerCase().contains(q)) o];
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => set(() => q = v.trim().toLowerCase()),
                  decoration: InputDecoration(hintText: 'Search $title', prefixIcon: const Icon(Icons.search_rounded), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Nothing found'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final o = shown[i];
                          final sub = subtitleOf?.call(o);
                          return ListTile(
                            dense: true,
                            title: Text(labelOf(o)),
                            subtitle: sub == null || sub.isEmpty ? null : Text(sub),
                            trailing: o == selected ? const Icon(Icons.check_rounded) : null,
                            onTap: () => Navigator.pop(ctx, (value: o)),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      });
    },
  );
}

/// Comma / newline separated list input that saves a `List<String>`.
class FChips extends StatelessWidget {
  const FChips({
    super.key,
    required this.label,
    required this.onSaved,
    this.initial = const [],
    this.hint,
    this.required = false,
  });
  final String label;
  final void Function(List<String>) onSaved;
  final List<String> initial;
  final String? hint;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return FField(
      label: label,
      hint: hint ?? 'Separate with commas',
      child: TextFormField(
        initialValue: initial.join(', '),
        decoration: const InputDecoration(hintText: 'value1, value2'),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        onSaved: (v) => onSaved((v ?? '')
            .split(RegExp(r'[,\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()),
      ),
    );
  }
}

/// A switch that participates in Form save via a FormField.
class FBoolField extends StatelessWidget {
  const FBoolField({
    super.key,
    required this.label,
    required this.onSaved,
    this.initial = false,
    this.hint,
  });
  final String label;
  final void Function(bool) onSaved;
  final bool initial;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      initialValue: initial,
      onSaved: (v) => onSaved(v ?? initial),
      builder: (state) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          subtitle: hint != null ? Text(hint!) : null,
          value: state.value ?? initial,
          onChanged: state.didChange,
        ),
      ),
    );
  }
}

/// Confirm dialog. Returns true if confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: message != null ? Text(message) : null,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppPalette.danger)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A tall, scrollable bottom sheet for lists and read-only content — a drag handle on top (pull it up or down to resize, down far enough to close),
/// a title, and a body that scrolls. [builder] gets the sheet's scroll controller: hand it to the ListView.
Future<T?> showTallSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, ScrollController controller) builder,
  Widget? trailing,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (ctx, controller) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 48, height: 5, decoration: BoxDecoration(color: ctx.lineColor, borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
          child: Row(children: [
            Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            if (trailing != null) trailing,
            IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Expanded(child: builder(ctx, controller)),
      ]),
    ),
  );
}
