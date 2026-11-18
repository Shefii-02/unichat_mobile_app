class UserModel {
  final int id;
  final String name;
  final String phone;
  final String? email;
  final String? avatar;
  final String role;
  final int companyId;
  final String? companyName;
  final String? companySlug;
  final String? waContactToken; // wa_chat_token for node backend auth
  final List<String> permissions;

  /// Access sections assigned to the user, main first (company_admin, administrators, sales,
  /// marketing, hr, accounts). Their permissions are already merged into [permissions].
  final List<String> accessSections;

  /// Feature modules the company's plan + add-ons include (see backend Modules::REGISTRY).
  /// `null` = unknown / no plan restriction → everything shown.
  final List<String>? entitledModules;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.avatar,
    required this.role,
    required this.companyId,
    this.companyName,
    this.companySlug,
    this.waContactToken,
    required this.permissions,
    this.accessSections = const [],
    this.entitledModules,
  });

  // Parses the raw user object (already unwrapped — just the "user" map)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final roleRaw = json['role'];
    final role = roleRaw is Map ? (roleRaw['name'] as String? ?? 'staff') : (roleRaw as String? ?? 'staff');

    final company = json['company'] as Map<String, dynamic>?;

    final perms = json['permissions'];
    final permissions = perms is List
        ? perms.map((e) => e.toString()).toList()
        : <String>[];

    final sections = json['access_sections'];
    final ent = company?['entitlements'] ?? json['entitlements'];
    List<String>? entitled;
    if (ent is Map && ent['all'] != true && ent['modules'] is List) {
      entitled = (ent['modules'] as List).map((e) => e.toString()).toList();
    }

    return UserModel(
      id:              json['id'] as int,
      name:            json['name'] as String? ?? '',
      phone:           json['phone'] as String? ?? '',
      email:           json['email'] as String?,
      avatar:          json['avatar'] as String?,
      role:            role,
      companyId:       company?['id'] as int? ?? json['company_id'] as int? ?? 0,
      companyName:     company?['name'] as String? ?? json['company_name'] as String?,
      companySlug:     company?['slug'] as String?,
      waContactToken:  company?['wa_chat_token'] as String?,
      permissions:     permissions,
      accessSections:  sections is List ? sections.map((e) => e.toString()).toList() : const [],
      entitledModules: entitled,
    );
  }

  // Stored to local cache — keeps all fields for offline use
  Map<String, dynamic> toJson() => {
    'id':               id,
    'name':             name,
    'phone':            phone,
    'email':            email,
    'avatar':           avatar,
    'role':             role,
    'company_id':       companyId,
    'company_name':     companyName,
    'company_slug':     companySlug,
    'wa_contact_token': waContactToken,
    'permissions':      permissions,
    'access_sections':  accessSections,
    if (entitledModules != null) 'entitlements': {'all': false, 'modules': entitledModules},
  };
}
