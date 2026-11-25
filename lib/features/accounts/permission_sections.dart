/// Which part of the app a permission belongs to — the same grouping the website's Roles and Staff Access screens use
/// (WA Chat, WA Cloud, Flow Builder, AI Agent, CRM, Leads … everything else is "System").
const permissionSectionOrder = <String>[
  'General', 'WA Chat', 'WA Cloud', 'Flow Builder', 'AI Agent', 'Instagram & Messenger', 'Meta Ads', 'CRM', 'Leads', 'Accounts', 'HR',
  'Website chat', 'Team chat', 'System',
];

const _byPrefix = <(String, String)>[
  ('pages.hr_', 'HR'), ('pages.my_', 'HR'), ('pages.sales_activity', 'HR'), ('pages.wa_chat_', 'WA Chat'), ('pages.', 'General'),
  ('wa_chat.', 'WA Chat'),
  ('wa_cloud.', 'WA Cloud'), ('templates.', 'WA Cloud'), ('campaigns.', 'WA Cloud'), ('surveys.', 'WA Cloud'), ('flow_builder.', 'Flow Builder'), ('otp.', 'WA Cloud'),
  ('phone_numbers.', 'WA Cloud'), ('inbox.', 'WA Cloud'), ('message_logs.', 'WA Cloud'),
  ('wa_agent.', 'AI Agent'), ('catalog.', 'AI Agent'),
  ('instagram.', 'Instagram & Messenger'), ('meta_ads.', 'Meta Ads'),
  ('contacts.', 'CRM'), ('labels.', 'CRM'), ('blacklist.', 'CRM'),
  ('leads.', 'Leads'), ('lead_assignment.', 'Leads'),
  ('accounts.', 'Accounts'), ('hr.', 'HR'), ('calendar.', 'HR'),
  ('widget_chat.', 'Website chat'), ('team_chat.', 'Team chat'),
];

String permissionSection(String key) {
  for (final p in _byPrefix) {
    if (key.startsWith(p.$1)) return p.$2;
  }
  return 'System';
}

/// Permissions arranged section → group → permissions, in the app's section order. [perms] items need `key`, `label`, `group`.
List<(String section, List<(String group, List<Map<String, dynamic>> perms)>)> sectioned(List<Map<String, dynamic>> perms) {
  final bySection = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final p in perms) {
    final s = permissionSection('${p['key']}');
    bySection.putIfAbsent(s, () => {}).putIfAbsent('${p['group'] ?? 'Other'}', () => []).add(p);
  }
  return [
    for (final s in permissionSectionOrder)
      if (bySection.containsKey(s)) (s, [for (final g in bySection[s]!.entries) (g.key, g.value)]),
  ];
}
