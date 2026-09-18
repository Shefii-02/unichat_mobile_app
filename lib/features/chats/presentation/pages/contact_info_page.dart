// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// A 1-1 chat's contact info — mirrors `ContactInfoPanel.tsx`: Info / Labels / Groups / Leads
/// tabs, sourced from the CRM contact matched by the chat's phone number (may be absent if the
/// number was never captured — every tab below tolerates that instead of erroring). Uses the
/// same general CRM endpoints (`/contacts`, `/labels`, `/staff`, `/leads`) other pages in this
/// app already call directly via `Api.*` — there's no dedicated wrapper class for those, unlike
/// the WA-Chat-specific `WaChatApi`.
class ContactInfoPage extends ConsumerStatefulWidget {
  const ContactInfoPage({
    super.key,
    required this.sessionName,
    required this.apiKey,
    required this.chatId,
    required this.chatName,
  });

  final String sessionName;
  final String apiKey;
  final String chatId;
  final String chatName;

  @override
  ConsumerState<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends ConsumerState<ContactInfoPage> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 4, vsync: this)..addListener(_onTabChanged);

  Rec? _contact;
  bool _contactLoading = true;
  String? _contactError;
  String? _labelsError;
  String? _pictureUrl;

  /// The real MSISDN behind an `@lid` chat id, resolved via the gateway's phone-resolve endpoint.
  /// Null while unresolved/unresolvable; irrelevant for `@c.us` chats, whose digits are the phone.
  String? _resolvedLidPhone;
  bool _resolvingLidPhone = false;

  List<Rec> _groups = [];
  bool _groupsLoading = false;
  bool _groupsFetched = false;

  List<Rec> _leads = [];
  bool _leadsLoading = false;
  bool _leadsFetched = false;
  bool _creatingLead = false;

  List<Rec> _allLabels = [];
  List<Rec> _contactLabels = [];

  List<Rec> _staffList = [];
  bool _showStaffPicker = false;
  bool _assigningStaff = false;
  bool _assigningLead = false;

  /// The chat id is a WhatsApp JID (`<digits>@c.us` for a real number, `<opaque>@lid` for a
  /// privacy id). The `@c.us` form's digits are the phone number directly; an `@lid` contact needs
  /// an extra gateway round trip (see [_resolveLidPhoneThenLoad]) — until that resolves, or if it
  /// can't, this stays empty and the contact simply won't match a CRM contact (same "not in CRM"
  /// empty state as a genuinely new number).
  String get _phoneDigits {
    if (widget.chatId.contains('@lid')) {
      final resolved = _resolvedLidPhone;
      return resolved == null ? '' : resolved.replaceAll(RegExp(r'\D'), '');
    }
    return widget.chatId.split('@').first.replaceAll(RegExp(r'\D'), '');
  }

  @override
  void initState() {
    super.initState();
    _resolveLidPhoneThenLoad();
    _loadAllLabels();
    _loadPicture();
  }

  /// For an `@lid` chat, asks the gateway to resolve the real phone number behind it before the
  /// first CRM contact lookup — otherwise that lookup always runs with empty digits and reports
  /// "not in CRM" even for a contact that genuinely is.
  Future<void> _resolveLidPhoneThenLoad() async {
    if (widget.chatId.contains('@lid')) {
      setState(() => _resolvingLidPhone = true);
      final phone = await WaChatApiService.resolveContactPhone(widget.sessionName, widget.apiKey, widget.chatId);
      if (!mounted) return;
      setState(() {
        _resolvedLidPhone = phone;
        _resolvingLidPhone = false;
      });
    }
    await _loadContact();
  }

  Future<void> _loadPicture() async {
    final url = await WaChatApiService.getContactProfilePicture(widget.sessionName, widget.apiKey, widget.chatId);
    if (mounted && url != null) setState(() => _pictureUrl = url);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 2 && !_groupsFetched) _loadGroups();
    if (_tabController.index == 3 && !_leadsFetched) _loadLeads();
  }

  Future<void> _loadContact() async {
    setState(() { _contactLoading = true; _contactError = null; });
    final digits = _phoneDigits;
    final last10 = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    if (last10.isEmpty) {
      setState(() { _contact = null; _contactLoading = false; });
      return;
    }
    try {
      // per_page=1 assumes the search term is specific enough to have one match — a last-10-digit
      // search should be, but if two contacts ever collide on it, only the first (most recently
      // created) comes back; that contact's real labels would then correctly show as empty here,
      // which looks identical to "labels aren't loading" without the phone number visible to
      // cross-check against, hence surfacing it in the CRM badge below.
      final rows = await Api.list('/contacts', query: {'search': last10, 'per_page': 1});
      if (!mounted) return;
      setState(() {
        _contact = rows.isNotEmpty ? rows.first : null;
        _contactLabels = (_contact?['labels'] as List?)?.cast<Rec>() ?? [];
        _contactLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Previously a silent catch that always presented as "Contact not in CRM" — indistinguishable
      // from a genuine no-match, which hid real causes (e.g. missing contacts.view permission).
      setState(() { _contact = null; _contactLoading = false; _contactError = apiErrorMessage(e); });
    }
  }

  Future<void> _loadAllLabels() async {
    try {
      final labels = await Api.list('/labels');
      if (mounted) setState(() { _allLabels = labels; _labelsError = null; });
    } catch (e) {
      if (mounted) setState(() => _labelsError = apiErrorMessage(e));
    }
  }

  Future<void> _loadGroups() async {
    setState(() { _groupsLoading = true; _groupsFetched = true; });
    try {
      final groups = await WaChatApiService.getSharedGroups(widget.sessionName, widget.apiKey, widget.chatId);
      if (!mounted) return;
      setState(() { _groups = groups; _groupsLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _groups = []; _groupsLoading = false; });
    }
  }

  Future<void> _loadLeads() async {
    final contactId = _contact?['id'];
    if (contactId == null) return;
    setState(() { _leadsLoading = true; _leadsFetched = true; });
    try {
      final res = await Api.list('/leads', query: {'contact_id': contactId, 'per_page': 10});
      if (!mounted) return;
      setState(() { _leads = res; _leadsLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _leads = []; _leadsLoading = false; });
    }
  }

  Future<void> _createLead() async {
    final contactId = _contact?['id'];
    if (contactId == null) return;
    setState(() => _creatingLead = true);
    try {
      await Api.post('/leads', data: {'contact_id': contactId, 'source': 'whatsapp_chat', 'stage': 'new'});
      _leadsFetched = false;
      await _loadLeads();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _creatingLead = false);
    }
  }

  /// Bottom sheet offering to assign this lead to an existing staff member, or to a brand-new one
  /// created on the spot — the two ways "assign lead to an employee" works here.
  Future<void> _openAssignLeadSheet(Rec lead) async {
    await _loadStaffIfNeeded();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: context.lineColor, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Assign Lead',
                      style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
              if (PermissionGuard.can('staff.manage'))
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
                  title: const Text('New employee'),
                  subtitle: const Text('Create a staff member and assign this lead to them'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _createEmployeeAndAssign(lead);
                  },
                ),
              const Divider(height: 1),
              Flexible(
                child: _staffList.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No employees yet', style: TextStyle(color: context.mutedColor)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: _staffList
                            .map((s) => ListTile(
                                  leading: CircleAvatar(
                                      radius: 16,
                                      child: Text(str(s['name'], '?').characters.first.toUpperCase(),
                                          style: const TextStyle(fontSize: 12))),
                                  title: Text(str(s['name'])),
                                  subtitle: Text(str(s['email'], '')),
                                  onTap: () {
                                    Navigator.of(sheetCtx).pop();
                                    _assignLead(lead, s['id']);
                                  },
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignLead(Rec lead, dynamic userId) async {
    setState(() => _assigningLead = true);
    final ok = await runAction(
      context,
      () => Api.post('/leads/${lead['id']}/assign', data: {'user_id': userId}),
      success: 'Lead assigned',
    );
    if (!mounted) return;
    setState(() => _assigningLead = false);
    if (ok) {
      _leadsFetched = false;
      await _loadLeads();
    }
  }

  /// Creates a brand-new staff member (same fields as the Staff & Roles page) and immediately
  /// assigns this lead to them.
  Future<void> _createEmployeeAndAssign(Rec lead) async {
    List<Rec> roles = const [];
    try {
      roles = await Api.list('/roles');
    } catch (_) {}
    if (!mounted) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'New employee',
      submitLabel: 'Create & assign',
      fields: (ctx) => [
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
        FText(
          label: 'Email',
          required: true,
          keyboardType: TextInputType.emailAddress,
          onSaved: (v) => data['email'] = v,
        ),
        FText(
          label: 'Password',
          required: true,
          obscure: true,
          hint: 'Min 8 characters',
          onSaved: (v) {
            data['password'] = v;
            data['password_confirmation'] = v;
          },
        ),
        if (roles.isNotEmpty)
          FSelect<Rec>(
            label: 'Role',
            options: roles,
            labelOf: (r) => str(r['label'] ?? r['name']),
            onSaved: (r) => r?['id'] != null ? data['role_id'] = r!['id'] : null,
          ),
        FText(
          label: 'Phone',
          keyboardType: TextInputType.phone,
          onSaved: (v) => v.isEmpty ? null : data['phone'] = v,
        ),
      ],
      onSubmit: () async {
        final res = await Api.post('/staff', data: data);
        final created = res['staff'] ?? res;
        _staffList = [..._staffList, created];
        final newId = created['id'];
        if (newId != null) {
          await Api.post('/leads/${lead['id']}/assign', data: {'user_id': newId});
        }
      },
    );
    if (ok) {
      _leadsFetched = false;
      await _loadLeads();
    }
  }

  /// The chat has no CRM contact yet — create one from the chat's own phone/name so a label has
  /// somewhere to attach. `wa_id` keeps the exact chat id on the record either way.
  Future<Rec?> _createContactForChat(List<dynamic> labelIds) async {
    final digits = _phoneDigits;
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not determine a phone number for this chat')));
      }
      return null;
    }
    final res = await Api.post('/contacts', data: {
      'phone': digits,
      if (widget.chatName.isNotEmpty) 'name': widget.chatName,
      'wa_id': widget.chatId,
      'label_ids': labelIds,
    });
    return (res['contact'] ?? res);
  }

  /// Full-set sync: writes the whole checked set in one request (adds several / removes others).
  /// Returns whether it succeeded, so callers like the label bottom sheet know whether to close.
  Future<bool> _saveLabels(List<dynamic> ids) async {
    try {
      if (_contact == null) {
        if (ids.isEmpty) return true;
        final created = await _createContactForChat(ids);
        if (created == null) return false;
        setState(() {
          _contact = created;
          _contactLabels = (created['labels'] as List?)?.cast<Rec>() ??
              _allLabels.where((l) => ids.contains(l['id'])).toList();
        });
      } else if (ids.isEmpty) {
        // The sync endpoint rejects an empty label_ids array — clear by removing each individually.
        for (final l in _contactLabels) {
          try {
            await Api.delete('/contacts/${_contact!['id']}/labels/${l['id']}');
          } catch (_) {}
        }
        setState(() => _contactLabels = []);
      } else {
        final res = await Api.post('/contacts/${_contact!['id']}/labels', data: {'label_ids': ids});
        final fresh = res['contact']?['labels'] ?? res['labels'];
        setState(() => _contactLabels =
            (fresh as List?)?.cast<Rec>() ?? _allLabels.where((l) => ids.contains(l['id'])).toList());
      }
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return false;
    }
  }

  /// Opens the "Add Label" bottom sheet: loads the company's CRM labels, lets the user multi-select
  /// which ones apply to this contact, and syncs the whole set on Save (see [_saveLabels]).
  Future<void> _openLabelsSheet() async {
    final draft = _contactLabels.map((l) => l['id']).toSet();
    var saving = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          Future<void> save() async {
            setSheetState(() => saving = true);
            final ok = await _saveLabels(draft.toList());
            if (ok && sheetCtx.mounted) {
              Navigator.of(sheetCtx).pop();
            } else {
              setSheetState(() => saving = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.35,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: context.lineColor, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                      child: Row(children: [
                        Expanded(
                          child: Text('CRM Labels',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: _allLabels.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _labelsError != null ? "Couldn't load labels — $_labelsError" : 'No labels available',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _labelsError != null ? AppPalette.danger : context.mutedColor),
                                ),
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              children: _allLabels
                                  .map((l) => CheckboxListTile(
                                        value: draft.contains(l['id']),
                                        onChanged: (v) =>
                                            setSheetState(() => v == true ? draft.add(l['id']) : draft.remove(l['id'])),
                                        secondary: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(color: _labelColor(l), shape: BoxShape.circle),
                                        ),
                                        title: Text(str(l['name'])),
                                      ))
                                  .toList(),
                            ),
                    ),
                    SafeArea(
                      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: FilledButton(
                        onPressed: saving ? null : save,
                        child: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeLabel(dynamic labelId) =>
      _saveLabels(_contactLabels.where((l) => l['id'] != labelId).map((l) => l['id']).toList());

  Future<void> _loadStaffIfNeeded() async {
    if (_staffList.isNotEmpty) return;
    try {
      final staff = await Api.list('/staff');
      if (mounted) setState(() => _staffList = staff);
    } catch (_) {}
  }

  Future<void> _assignStaff(dynamic staffId) async {
    if (_contact == null) return;
    setState(() => _assigningStaff = true);
    try {
      final res = await Api.put('/contacts/${_contact!['id']}', data: {'assigned_to': staffId});
      if (!mounted) return;
      setState(() {
        _contact = res['contact'] ?? res;
        _showStaffPicker = false;
        _assigningStaff = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _assigningStaff = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Color _labelColor(Rec l) {
    final c = l['color'] as String?;
    if (c == null || !c.startsWith('#')) return AppPalette.muted;
    try {
      return Color(int.parse(c.replaceFirst('#', '0xff')));
    } catch (_) {
      return AppPalette.muted;
    }
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasContact = _contact != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Info')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                AppAvatar(name: widget.chatName, imageUrl: _pictureUrl, size: 72),
                const SizedBox(height: 10),
                Text(widget.chatName.isNotEmpty ? widget.chatName : _phoneDigits,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (_phoneDigits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_phoneDigits, style: TextStyle(color: context.mutedColor, fontSize: 13)),
                  )
                else if (_resolvingLidPhone)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Resolving phone number…',
                        style: TextStyle(color: context.mutedColor, fontSize: 12, fontStyle: FontStyle.italic)),
                  )
                else if (widget.chatId.contains('@lid'))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Phone number unavailable',
                        style: TextStyle(color: context.mutedColor, fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(widget.chatId,
                      style: TextStyle(color: context.mutedColor, fontSize: 10, fontFamily: 'monospace')),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasContact ? AppPalette.success.withValues(alpha: 0.15) : context.altSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _contactLoading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(hasContact ? Icons.verified_user_rounded : Icons.person_off_rounded,
                              size: 12, color: hasContact ? AppPalette.success : context.mutedColor),
                          const SizedBox(width: 4),
                          Text(hasContact ? 'In CRM' : 'Not saved in CRM',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: hasContact ? AppPalette.success : context.mutedColor)),
                        ]),
                ),
                // Cross-check: shows which contact actually matched, so a wrong-contact match (two
                // contacts colliding on the same last-10-digit search) is visible instead of just
                // looking like "labels aren't loading".
                if (hasContact && str(_contact!['phone'], '') != _phoneDigits && _phoneDigits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Matched CRM contact: ${str(_contact!['phone'])} (${str(_contact!['name'], 'no name')})',
                        style: TextStyle(fontSize: 10, color: AppPalette.warning)),
                  ),
                if (_contactError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                    child: Column(children: [
                      Text("Couldn't load CRM contact — $_contactError",
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppPalette.danger)),
                      TextButton(onPressed: _resolveLidPhoneThenLoad, child: const Text('Retry')),
                    ]),
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppPalette.accent,
            unselectedLabelColor: context.mutedColor,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: '🏷️ Info'),
              Tab(text: '🔖 Labels'),
              Tab(text: '👥 Groups'),
              Tab(text: '🎯 Leads'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _infoTab(hasContact),
                _labelsTab(hasContact),
                _groupsTab(),
                _leadsTab(hasContact),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
            if (action != null) action,
          ],
        ),
      );

  Widget _divider() => Divider(height: 1, color: context.lineColor);

  // ── Info tab ────────────────────────────────────────────────────────────────

  // Always a single stable ListView (see the note on _groupsTab for why) — loading/no-contact/
  // loaded are all just different `children`, never a different outer widget type.
  Widget _infoTab(bool hasContact) {
    return ListView(
      children: [
        if (_contactLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
        else if (!hasContact)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Contact not in CRM yet', style: TextStyle(color: context.mutedColor, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Add a label below to create one, or wait for the AI Agent to respond.',
                  textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor.withValues(alpha: 0.7), fontSize: 12)),
              const SizedBox(height: 20),
              _labelsSection(),
            ]),
          )
        else ...[
          _assignedStaffSection(),
          _divider(),
          _crmDetailsSection(),
          _divider(),
          _labelsSection(),
        ],
      ],
    );
  }

  Widget _assignedStaffSection() {
    final assigned = _contact?['assigned_to'] as Rec?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Assigned Staff',
            action: TextButton(
              onPressed: () {
                setState(() => _showStaffPicker = !_showStaffPicker);
                if (_showStaffPicker) _loadStaffIfNeeded();
              },
              child: Text(_showStaffPicker ? 'Cancel' : '+ Assign'),
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _showStaffPicker
              ? (_staffList.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Loading staff…', style: TextStyle(color: context.mutedColor, fontSize: 12)))
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView(
                        shrinkWrap: true,
                        children: _staffList
                            .map((s) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: CircleAvatar(
                                      radius: 14,
                                      child: Text(str(s['name'], '?').characters.first.toUpperCase(),
                                          style: const TextStyle(fontSize: 12))),
                                  title: Text(str(s['name']), style: const TextStyle(fontSize: 13)),
                                  subtitle: Text(str(s['email'], ''), style: const TextStyle(fontSize: 11)),
                                  onTap: _assigningStaff ? null : () => _assignStaff(s['id']),
                                ))
                            .toList(),
                      ),
                    ))
              : (assigned != null
                  ? Row(children: [
                      CircleAvatar(
                          backgroundColor: const Color(0xFFEDE9FE),
                          child: Text(str(assigned['name'], 'S').characters.first.toUpperCase(),
                              style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(str(assigned['name'], 'Staff'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(str(assigned['email'], ''), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                      ]),
                    ])
                  : Text('Not assigned to any staff', style: TextStyle(color: context.mutedColor, fontSize: 13))),
        ),
      ],
    );
  }

  Widget _crmDetailsSection() {
    final c = _contact!;
    final score = c['lead_score'];
    final scoreColor = score is num
        ? (score >= 76 ? AppPalette.danger : (score >= 51 ? AppPalette.warning : context.mutedColor))
        : context.mutedColor;
    final email = str(c['email'], '');
    final company = str(c['company_name'], '');
    final stage = str(c['lead_stage'], '');
    final summary = str(c['conversation_summary'], '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CRM DETAILS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          if (email.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('📧 $email', style: const TextStyle(fontSize: 13))),
          if (company.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('🏢 $company', style: const TextStyle(fontSize: 13))),
          if (stage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: '🎯 Stage: '),
                TextSpan(text: stage, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]), style: const TextStyle(fontSize: 13)),
            ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: '📊 Lead Score: '),
                TextSpan(text: '$score/100', style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor)),
              ]), style: const TextStyle(fontSize: 13)),
            ),
          if (summary.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(6)),
              child: Text('💬 $summary', style: TextStyle(fontSize: 11, color: context.mutedColor, height: 1.4)),
            ),
          if (email.isEmpty && company.isEmpty && stage.isEmpty && score == null && summary.isEmpty)
            Text('No CRM details yet', style: TextStyle(color: context.mutedColor, fontSize: 12)),
        ],
      ),
    );
  }

  // ── Labels tab (also embedded, condensed, at the bottom of Info) ───────────

  Widget _labelsTab(bool hasContact) {
    return ListView(
      children: [
        if (_contactLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
        else
          _labelsSection(),
      ],
    );
  }

  Widget _labelsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CRM LABELS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
              TextButton.icon(
                onPressed: _openLabelsSheet,
                icon: const Icon(Icons.label_rounded, size: 14),
                label: Text(_contactLabels.isNotEmpty ? 'Edit labels' : '+ Add to labels',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_contactLabels.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _contactLabels
                  .map((l) => Chip(
                        label: Text('🏷️ ${str(l['name'])}', style: TextStyle(color: _labelColor(l), fontSize: 12)),
                        backgroundColor: _labelColor(l).withValues(alpha: 0.15),
                        deleteIcon: Icon(Icons.close_rounded, size: 14, color: _labelColor(l)),
                        onDeleted: () => _removeLabel(l['id']),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            )
          else
            Text(hasContactForLabels ? 'No labels assigned' : 'Contact not in CRM',
                style: TextStyle(color: context.mutedColor, fontSize: 12)),
        ],
      ),
    );
  }

  bool get hasContactForLabels => _contact != null;

  // ── Groups tab ──────────────────────────────────────────────────────────────

  // A single ListView is always the child here, regardless of loading/empty/loaded state — only
  // its `children` differ. Swapping between Center/ListView/ListView.separated as RefreshIndicator's
  // direct child (the previous shape) changes the render-tree structure under a Scrollable-sensitive
  // ancestor on every load, which is the pattern behind Flutter's
  // "!semantics.parentDataDirty" assertion when an accessibility service (VoiceOver/TalkBack) is
  // scanning the tree mid-transition. `physics: AlwaysScrollableScrollPhysics` keeps pull-to-refresh
  // working even while the list's content is short (loading/empty states barely fill the viewport).
  Widget _groupsTab() {
    return RefreshIndicator(
      onRefresh: () {
        _groupsFetched = false;
        return _loadGroups();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_groupsLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
          else if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 44),
              child: Center(
                child: Column(children: [
                  Icon(Icons.groups_rounded, size: 32, color: context.mutedColor.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('Not in any shared groups', style: TextStyle(color: context.mutedColor, fontSize: 13)),
                ]),
              ),
            )
          else
            for (var i = 0; i < _groups.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < _groups.length - 1 ? 8 : 0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.success.withValues(alpha: 0.08),
                    border: Border.all(color: AppPalette.success.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const CircleAvatar(backgroundColor: Color(0xFFDCFCE7), child: Text('👥')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(str(_groups[i]['name'], 'Group'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(str(_groups[i]['id'], ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: context.mutedColor, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
        ],
      ),
    );
  }

  // ── Leads tab ───────────────────────────────────────────────────────────────

  Widget _leadsTab(bool hasContact) {
    if (!hasContact) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Contact not in CRM — no lead history available.',
              textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor, fontSize: 13)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LEAD HISTORY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
              FilledButton(
                onPressed: _creatingLead ? null : _createLead,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: _creatingLead
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('+ Lead', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        // A single ListView is always the Expanded's child here, regardless of loading/empty/loaded
        // state — only its `children` differ (see the matching note on _groupsTab, same fix for the
        // same "!semantics.parentDataDirty" pattern).
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_leadsLoading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
              else if (_leads.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 44),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.trending_up_rounded, size: 32, color: context.mutedColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text('No leads yet.', style: TextStyle(color: context.mutedColor)),
                      const SizedBox(height: 2),
                      Text('Tap "+ Lead" to create one.', style: TextStyle(color: context.mutedColor, fontSize: 11)),
                    ]),
                  ),
                )
              else
                for (var i = 0; i < _leads.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i < _leads.length - 1 ? 8 : 0),
                    child: _leadCard(_leads[i]),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _leadCard(Rec lead) {
    final stage = str(lead['stage'], 'new');
    final stageColor = stage == 'won' ? AppPalette.success : (stage == 'lost' ? AppPalette.danger : AppPalette.info);
    final category = lead['category'];
    final categoryName = category is Map ? str(category['name'], '') : '';
    // Per-lead assignment — distinct from the contact-level "Assigned Staff" above (Info tab): a
    // lead can be owned by a different staff member than whoever the contact itself is assigned
    // to, e.g. after a handoff.
    final leadAssignee = lead['assigned_to'];
    final leadAssigneeName = leadAssignee is Map ? str(leadAssignee['name'], '') : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(str(lead['title'], 'Lead #${lead['id']}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              StatusPill(stage, color: stageColor),
            ],
          ),
          if (categoryName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('🏷️ $categoryName', style: TextStyle(fontSize: 12, color: context.mutedColor)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    leadAssigneeName.isNotEmpty ? '👤 Assigned: $leadAssigneeName' : '👤 Unassigned',
                    style: TextStyle(
                      fontSize: 12,
                      color: leadAssigneeName.isNotEmpty ? context.mutedColor : AppPalette.warning,
                      fontWeight: leadAssigneeName.isNotEmpty ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ),
                if (PermissionGuard.can('leads.manage'))
                  TextButton(
                    onPressed: _assigningLead ? null : () => _openAssignLeadSheet(lead),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
                    child: Text(leadAssigneeName.isNotEmpty ? 'Reassign' : 'Assign', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          if (lead['value'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('₹${lead['value']}', style: const TextStyle(color: AppPalette.success, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_fmtDate(str(lead['created_at'], '')), style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ),
        ],
      ),
    );
  }
}
