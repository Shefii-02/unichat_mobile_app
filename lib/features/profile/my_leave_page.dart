import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/attendance/leave_request.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// My leave — the signed-in user's own requests (GET /hr/leave), with apply and cancel.
class MyLeavePage extends ConsumerStatefulWidget {
  const MyLeavePage({super.key});
  @override
  ConsumerState<MyLeavePage> createState() => _MyLeavePageState();
}

class _MyLeavePageState extends ConsumerState<MyLeavePage> {
  List<Rec> _rows = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Api.list('/hr/leave');
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    await requestLeave(context, ref);
    if (mounted) _load();
  }

  Future<void> _cancel(Rec l) async {
    if (!await confirm(
      context,
      title: 'Cancel this leave request?',
      confirmLabel: 'Cancel request',
      destructive: true,
    ))
      return;
    if (!mounted) return;
    final ok = await runAction(
      context,
      () => Api.post('/hr/leave/${l['id']}/cancel'),
      success: 'Request cancelled.',
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My leave')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _apply,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child:
            _loading
                ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
                : _error != null
                ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    Text(
                      apiErrorMessage(_error!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.mutedColor),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                )
                : _rows.isEmpty
                ? ListView(
                  children: [
                    const SizedBox(height: 140),
                    Icon(
                      Icons.event_available_outlined,
                      size: 52,
                      color: context.mutedColor,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'No leave requests yet',
                        style: TextStyle(color: context.mutedColor),
                      ),
                    ),
                  ],
                )
                : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final l = _rows[i];
                    final type =
                        l['leave_type'] is Map
                            ? (l['leave_type'] as Map)
                            : const {};
                    final status = str(l['status'], 'pending');
                    return Container(
                      decoration: BoxDecoration(
                        color: context.altSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          '${str(type['name'], 'Leave')} · ${str(l['days'], '1')} day(s)',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${str(l['start_date']).split('T').first} → ${str(l['end_date']).split('T').first}${l['reason'] != null ? '\n${l['reason']}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.mutedColor,
                          ),
                        ),
                        isThreeLine: l['reason'] != null,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusPill(status),
                            if (status == 'pending')
                              GestureDetector(
                                onTap: () => _cancel(l),
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppPalette.danger,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
