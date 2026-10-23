import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

// Personal sticky notes + to-do list, floating over every screen (same feature as the web app).
//  • Two draggable circles, same style: 📝 notes and ✅ to-do. Tap = show / hide.
//  • "＋ New note" / "＋ New to-do" pills appear above a circle while its layer is on.
//  • Notes (text, colour, folded, delete) sync with the server per user; where things sit on *this* phone and
//    whether they are showing are remembered on the device only, so moving things here never rearranges the web.
//  • The to-do card lists your open CRM tasks (assigned to you): tick to complete, add one quickly.

const _bubble = 52.0;
const _palette = [
  Color(0xFFFDE68A), Color(0xFFFECACA), Color(0xFFFED7AA), Color(0xFFBBF7D0), Color(0xFFBFDBFE),
  Color(0xFFDDD6FE), Color(0xFFFBCFE8), Color(0xFFE5E7EB), Color(0xFFA7F3D0), Color(0xFFFEF08A),
];

Color _hex(String? h) {
  final v = int.tryParse((h ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? _palette.first : Color(0xFF000000 | v);
}

String _toHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
Color _ink(Color c) => c.computeLuminance() < 0.4 ? Colors.white : const Color(0xFF1F2937);

/// Settings switch: show the floating notes / to-do circles on the Home page (device-local, default on).
const kStickyEnabledKey = 'sticky_enabled';
class StickyEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => LocalStorage.getBool(kStickyEnabledKey, defaultValue: true);
  void set(bool v) {
    state = v;
    LocalStorage.setBool(kStickyEnabledKey, v);
  }
}

final stickyEnabledProvider = NotifierProvider<StickyEnabledNotifier, bool>(StickyEnabledNotifier.new);

/// Wrap the Home page with this. Renders nothing until signed in and unlocked.
class StickyOverlay extends ConsumerWidget {
  const StickyOverlay({super.key, required this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    final enabled = ref.watch(stickyEnabledProvider);
    final base = child ?? const SizedBox.shrink();
    if (user == null || locked || !enabled) return base;
    return Stack(
      children: [
        base,
        // own Overlay so text fields in the cards have the ancestor they need (the app Navigator's is below us)
        Overlay(initialEntries: [
          OverlayEntry(builder: (_) => Material(type: MaterialType.transparency, child: _StickyLayer(userId: user.id))),
        ]),
      ],
    );
  }
}

class _Note {
  _Note(Map<String, dynamic> j)
      : id = j['id'] as int,
        title = (j['title'] ?? '').toString(),
        content = (j['content'] ?? '').toString(),
        color = _hex(j['color']?.toString()),
        minimized = j['minimized'] == true || j['minimized'] == 1;
  final int id;
  String title;
  String content;
  Color color;
  bool minimized;
}

class _StickyLayer extends StatefulWidget {
  const _StickyLayer({required this.userId});
  final int userId;
  @override
  State<_StickyLayer> createState() => _StickyLayerState();
}

class _StickyLayerState extends State<_StickyLayer> {
  List<_Note> _notes = [];
  Color _defaultColor = _palette.first;
  bool _notesOn = false, _todoOn = false;
  final Map<String, Offset> _pos = {}; // 'notes' | 'todo' | 'card:todo' | 'note:<id>'
  String _error = '';
  int _todoFocus = 0;
  final _timers = <int, Timer>{};

  String get _k => 'sticky_v1_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _restoreLocal();
    _load();
  }

  @override
  void dispose() {
    for (final t in _timers.values) { t.cancel(); }
    super.dispose();
  }

  void _restoreLocal() {
    try {
      final m = LocalStorage.getJson(_k);
      if (m == null) return;
      _notesOn = m['notes_on'] == true;
      _todoOn = m['todo_on'] == true;
      (m['pos'] as Map?)?.forEach((k, v) {
        if (v is List && v.length == 2) _pos['$k'] = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      });
    } catch (_) {}
  }

  void _persist() {
    try {
      LocalStorage.setJson(_k, {
        'notes_on': _notesOn,
        'todo_on': _todoOn,
        'pos': _pos.map((k, v) => MapEntry(k, [v.dx, v.dy])),
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final res = await Api.raw.get('/sticky-notes');
      final d = res.data is Map ? res.data as Map : const {};
      final settings = d['settings'] is Map ? d['settings'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _notes = ((d['notes'] as List?) ?? const []).map((e) => _Note(Map<String, dynamic>.from(e as Map))).toList();
        _defaultColor = _hex(settings['default_color']?.toString());
      });
    } catch (_) {/* widget is a bonus — never block the app */}
  }

  // ── server writes (notes only) ──
  void _save(_Note n, {int delayMs = 500}) {
    _timers[n.id]?.cancel();
    _timers[n.id] = Timer(Duration(milliseconds: delayMs), () async {
      try {
        await Api.raw.put('/sticky-notes/${n.id}', data: {
          'title': n.title, 'content': n.content, 'color': _toHex(n.color), 'minimized': n.minimized,
        });
      } catch (_) { if (mounted) setState(() => _error = 'Could not save — check your connection.'); }
    });
  }

  Future<void> _addNote(Size size) async {
    setState(() => _error = '');
    try {
      final res = await Api.raw.post('/sticky-notes', data: {'color': _toHex(_defaultColor), 'width': 220, 'height': 160});
      final note = _Note(Map<String, dynamic>.from((res.data as Map)['note'] as Map));
      setState(() {
        _notes.add(note);
        _pos['note:${note.id}'] = Offset(24.0 + (_notes.length % 6) * 18, 90.0 + (_notes.length % 6) * 18);
      });
      _persist();
    } catch (e) { setState(() => _error = apiErrorMessage(e)); }
  }

  Future<void> _deleteNote(_Note n) async {
    setState(() { _notes.remove(n); _pos.remove('note:${n.id}'); });
    _persist();
    try { await Api.delete('/sticky-notes/${n.id}'); } catch (_) { setState(() => _error = 'Could not delete — check your connection.'); }
  }

  Offset _clamp(Offset o, Size s, Size item) =>
      Offset(o.dx.clamp(0.0, (s.width - item.width).clamp(0.0, double.infinity)), o.dy.clamp(0.0, (s.height - item.height).clamp(0.0, double.infinity)));

  void _move(String key, Offset delta, Size screen, Size item, Offset fallback) {
    final cur = _pos[key] ?? fallback;
    setState(() => _pos[key] = _clamp(cur + delta, screen, item));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => _buildLayer(context, c.biggest));

  Widget _buildLayer(BuildContext context, Size screen) {
    const bottomSafe = 0.0;
    final notesFallback = Offset(screen.width - _bubble - 14, screen.height - _bubble - bottomSafe - 90);
    final todoFallback = Offset(notesFallback.dx - _bubble - 12, notesFallback.dy);
    final notesPos = _clamp(_pos['notes'] ?? notesFallback, screen, const Size(_bubble, _bubble));
    final todoPos = _clamp(_pos['todo'] ?? todoFallback, screen, const Size(_bubble, _bubble));

    return Stack(children: [
      if (_notesOn)
        for (final n in _notes)
          _NoteCard(
            key: ValueKey('note${n.id}'),
            note: n,
            pos: _clamp(_pos['note:${n.id}'] ?? const Offset(24, 100), screen, Size(220, n.minimized ? 36 : 160)),
            onMove: (d) => _move('note:${n.id}', d, screen, Size(220, n.minimized ? 36 : 160), const Offset(24, 100)),
            onMoveEnd: _persist,
            onChanged: (colorPicked) {
              if (colorPicked) _defaultColor = n.color;
              setState(() {});
              _save(n, delayMs: colorPicked ? 150 : 500);
            },
            onDelete: () => _deleteNote(n),
          ),
      if (_todoOn)
        _TodoCard(
          userId: widget.userId,
          color: _defaultColor,
          focusSignal: _todoFocus,
          pos: _clamp(_pos['card:todo'] ?? Offset(screen.width - 270, 80), screen, const Size(260, 60)),
          onMove: (d) => _move('card:todo', d, screen, const Size(260, 60), Offset(screen.width - 270, 80)),
          onMoveEnd: _persist,
          onClose: () { setState(() => _todoOn = false); _persist(); },
        ),
      _Bubble(
        icon: '📝', label: 'Sticky notes', color: _defaultColor, on: _notesOn, pos: notesPos, badge: _notes.length,
        onMove: (d) => _move('notes', d, screen, const Size(_bubble, _bubble), notesFallback),
        onMoveEnd: _persist,
        onTap: () { setState(() => _notesOn = !_notesOn); _persist(); },
        pill: _notesOn ? ('＋ New note', () => _addNote(screen)) : null,
        error: _error.isEmpty ? null : _error,
        onErrorTap: () => setState(() => _error = ''),
      ),
      _Bubble(
        icon: '✅', label: 'To-do list', color: _defaultColor, on: _todoOn, pos: todoPos,
        onMove: (d) => _move('todo', d, screen, const Size(_bubble, _bubble), todoFallback),
        onMoveEnd: _persist,
        onTap: () { setState(() => _todoOn = !_todoOn); _persist(); },
        pill: _todoOn ? ('＋ New to-do', () => setState(() => _todoFocus++)) : null,
      ),
    ]);
  }
}

/// A draggable floating circle — the notes and the to-do circles are both this, so they look the same.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon, required this.label, required this.color, required this.on, required this.pos,
    required this.onMove, required this.onMoveEnd, required this.onTap, this.badge = 0, this.pill, this.error, this.onErrorTap,
  });
  final String icon, label;
  final Color color;
  final bool on;
  final Offset pos;
  final int badge;
  final void Function(Offset delta) onMove;
  final VoidCallback onMoveEnd, onTap;
  final (String, VoidCallback)? pill;
  final String? error;
  final VoidCallback? onErrorTap;

  @override
  Widget build(BuildContext context) {
    // The hit area is larger than the circle: children outside a Stack's bounds can't be tapped, so the pill
    // and error bubble need to live inside it (the empty parts don't swallow touches).
    const padX = 74.0, padTop = 100.0;
    return Positioned(
      left: pos.dx - padX,
      top: pos.dy - padTop,
      width: _bubble + padX * 2,
      height: _bubble + padTop,
      child: Stack(clipBehavior: Clip.none, children: [
        if (pill != null)
          Positioned(
            bottom: _bubble + 8,
            left: padX + _bubble / 2 - 60,
            width: 120,
            child: Center(
              child: Material(
                color: Colors.white,
                elevation: 4,
                shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade300)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: pill!.$2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text(pill!.$1, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  ),
                ),
              ),
            ),
          ),
        if (error != null)
          Positioned(
            bottom: _bubble + 46,
            left: 0,
            width: 200,
            child: GestureDetector(
              onTap: onErrorTap,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
                child: Text(error!, style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
              ),
            ),
          ),
        Positioned(
          left: padX,
          bottom: 0,
          width: _bubble,
          height: _bubble,
          child: Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          onTap: onTap,
          onPanUpdate: (d) => onMove(d.delta),
          onPanEnd: (_) => onMoveEnd(),
          child: Semantics(
            button: true,
            label: '$label — tap to ${on ? 'hide' : 'show'}, drag to move',
            child: Opacity(
              opacity: on ? 1 : 0.75,
              child: Container(
                width: _bubble,
                height: _bubble,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: on ? Colors.grey.shade800 : Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Text(icon, style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          ]),
        ),
      ]),
    );
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({super.key, required this.note, required this.pos, required this.onMove, required this.onMoveEnd, required this.onChanged, required this.onDelete});
  final _Note note;
  final Offset pos;
  final void Function(Offset) onMove;
  final VoidCallback onMoveEnd, onDelete;
  final void Function(bool colorPicked) onChanged;
  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _palette_ = false;
  late final _title = TextEditingController(text: widget.note.title);
  late final _body = TextEditingController(text: widget.note.content);

  @override
  void dispose() { _title.dispose(); _body.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final ink = _ink(n.color);
    return Positioned(
      left: widget.pos.dx,
      top: widget.pos.dy,
      width: 220,
      height: n.minimized ? null : 160,
      child: Container(
        decoration: BoxDecoration(color: n.color, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 14, offset: Offset(0, 6))]),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: n.minimized ? MainAxisSize.min : MainAxisSize.max, children: [
          GestureDetector(
            onPanUpdate: (d) => widget.onMove(d.delta),
            onPanEnd: (_) => widget.onMoveEnd(),
            child: Container(
              color: Colors.black.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              height: 36,
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    maxLength: 100,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12),
                    decoration: InputDecoration(isDense: true, border: InputBorder.none, counterText: '', hintText: 'Title', hintStyle: TextStyle(color: ink.withValues(alpha: 0.5))),
                    onChanged: (v) { n.title = v; widget.onChanged(false); },
                  ),
                ),
                _hdrBtn(ink, Icons.palette_outlined, () => setState(() => _palette_ = !_palette_)),
                _hdrBtn(ink, n.minimized ? Icons.unfold_more_rounded : Icons.remove_rounded, () { n.minimized = !n.minimized; widget.onChanged(false); }),
                _hdrBtn(ink, Icons.delete_outline_rounded, () async {
                  if (n.content.trim().isEmpty) { widget.onDelete(); return; }
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete this sticky note?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
                    ),
                  );
                  if (ok == true) widget.onDelete();
                }),
              ]),
            ),
          ),
          if (_palette_)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () { n.color = c; setState(() => _palette_ = false); widget.onChanged(true); },
                    child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: n.color == c ? Colors.black : Colors.black26, width: n.color == c ? 2 : 1))),
                  ),
              ]),
            ),
          if (!n.minimized)
            Expanded(
              child: TextField(
                controller: _body,
                maxLength: 5000,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(color: ink, fontSize: 13),
                decoration: InputDecoration(border: InputBorder.none, counterText: '', contentPadding: const EdgeInsets.all(8), hintText: 'Write a note…', hintStyle: TextStyle(color: ink.withValues(alpha: 0.5))),
                onChanged: (v) { n.content = v; widget.onChanged(false); },
              ),
            ),
        ]),
      ),
    );
  }

  Widget _hdrBtn(Color ink, IconData i, VoidCallback onTap) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(5), child: Icon(i, size: 16, color: ink)));
}

class _TodoCard extends StatefulWidget {
  const _TodoCard({required this.userId, required this.color, required this.focusSignal, required this.pos, required this.onMove, required this.onMoveEnd, required this.onClose});
  final int userId;
  final Color color;
  final int focusSignal;
  final Offset pos;
  final void Function(Offset) onMove;
  final VoidCallback onMoveEnd, onClose;
  @override
  State<_TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<_TodoCard> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _adding = false;
  int? _busy;
  String _err = '';
  final _draft = TextEditingController();
  final _focus = FocusNode();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant _TodoCard old) {
    super.didUpdateWidget(old);
    if (widget.focusSignal != old.focusSignal) _focus.requestFocus();
  }

  @override
  void dispose() { _poll?.cancel(); _draft.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await Api.list('/crm/tasks', query: {'mine': 1, 'status': 'open', 'exclude_type': 'followup'});
      if (mounted) setState(() { _items = rows; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _complete(Map<String, dynamic> t) async {
    setState(() { _busy = t['id'] as int?; _err = ''; });
    try {
      await Api.post('/crm/tasks/${t['id']}/toggle');
      if (mounted) setState(() => _items.removeWhere((x) => x['id'] == t['id']));
    } catch (_) { if (mounted) setState(() => _err = 'Could not update the task.'); }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _add() async {
    final title = _draft.text.trim();
    if (title.isEmpty) return;
    setState(() { _adding = true; _err = ''; });
    try {
      final created = await Api.post('/crm/tasks', data: {'title': title, 'type': 'todo', 'assigned_to': widget.userId});
      if (mounted) setState(() { _items.add(created); _draft.clear(); });
    } catch (_) { if (mounted) setState(() => _err = 'Could not add the task.'); }
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final ink = _ink(widget.color);
    final maxH = MediaQuery.of(context).size.height * 0.55;
    const dot = {'low': Color(0xFF9CA3AF), 'medium': Color(0xFFF59E0B), 'high': Color(0xFFEF4444)};
    return Positioned(
      left: widget.pos.dx,
      top: widget.pos.dy,
      width: 260,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 14, offset: Offset(0, 6))]),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onPanUpdate: (d) => widget.onMove(d.delta),
            onPanEnd: (_) => widget.onMoveEnd(),
            child: Container(
              color: Colors.black.withValues(alpha: 0.08),
              height: 36,
              padding: const EdgeInsets.only(left: 10),
              child: Row(children: [
                Expanded(child: Text('✅ My to-do (${_items.length})', style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12))),
                InkWell(onTap: widget.onClose, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close_rounded, size: 16, color: ink))),
              ]),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                if (_loading) Text('Loading…', style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.7)))
                else if (_items.isEmpty) Text('Nothing to do — nice.', style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.7))),
                for (final t in _items)
                  InkWell(
                    onTap: _busy == t['id'] ? null : () => _complete(t),
                    child: Opacity(
                      opacity: _busy == t['id'] ? 0.5 : 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.check_box_outline_blank_rounded, size: 20, color: ink),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text.rich(TextSpan(children: [
                                TextSpan(text: '● ', style: TextStyle(color: dot['${t['priority']}'] ?? Colors.grey)),
                                TextSpan(text: '${t['title']}'),
                              ]), style: TextStyle(fontSize: 13, color: ink)),
                              if (t['due_at'] != null) _due(t['due_at'], ink),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                if (_err.isNotEmpty) Text(_err, style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A000000)))),
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _draft,
                  focusNode: _focus,
                  maxLength: 200,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF111111)),
                  decoration: InputDecoration(
                    isDense: true, counterText: '', hintText: 'Add a to-do…', filled: true, fillColor: Colors.white.withValues(alpha: 0.6),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                  ),
                ),
              ),
              InkWell(
                onTap: _adding ? null : _add,
                child: Padding(padding: const EdgeInsets.all(8), child: _adding ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ink)) : Icon(Icons.add_rounded, color: ink)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _due(Object? v, Color ink) {
    final d = DateTime.tryParse('$v')?.toLocal();
    if (d == null) return const SizedBox.shrink();
    String p(int n) => n.toString().padLeft(2, '0');
    final overdue = d.isBefore(DateTime.now());
    return Text('🗓 ${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}', style: TextStyle(fontSize: 10, color: overdue ? const Color(0xFFB91C1C) : ink.withValues(alpha: 0.75)));
  }
}
