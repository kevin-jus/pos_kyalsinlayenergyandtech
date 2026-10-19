import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wifi_sync.dart';
import 'ui_translation.dart';

enum UserRole { owner, admin, manager, cashier }
extension UserRoleText on UserRole { String get label => name[0].toUpperCase() + name.substring(1); }
enum PosPermission { sell, inventory, customers, reports, savedSaleChange, saleDelete, exportData, restoreBackup, users, security, device, branch, license }

class PosUser {
  PosUser({required this.id, required this.name, required this.username, required this.role, required this.salt, required this.pinHash, this.active = true});
  final String id; String name; String username; UserRole role; String salt; String pinHash; bool active;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'username': username, 'role': role.name, 'salt': salt, 'pinHash': pinHash, 'active': active};
  factory PosUser.fromJson(Map<String, dynamic> j) => PosUser(id: j['id'] as String, name: j['name'] as String? ?? '', username: j['username'] as String? ?? '', role: UserRole.values.firstWhere((x) => x.name == j['role'], orElse: () => UserRole.cashier), salt: j['salt'] as String? ?? '', pinHash: j['pinHash'] as String? ?? '', active: j['active'] as bool? ?? true);
}

class AuditEvent {
  AuditEvent({required this.id, required this.action, required this.actor, required this.deviceId, required this.at, this.detail = '', this.signature = ''});
  final String id, action, actor, deviceId, detail; final DateTime at; String signature;
  Map<String, dynamic> toJson() => {'id': id, 'action': action, 'actor': actor, 'deviceId': deviceId, 'detail': detail, 'at': at.toIso8601String(), 'signature': signature};
  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(id: j['id'] as String, action: j['action'] as String? ?? '', actor: j['actor'] as String? ?? '', deviceId: j['deviceId'] as String? ?? '', detail: j['detail'] as String? ?? '', at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(), signature: j['signature'] as String? ?? '');
}

/// AES-GCM key material lives in the platform keychain/keystore, never in the
/// POS database. The same vault encrypts backups and protected local settings.
class SecureVault {
  SecureVault._(); static final instance = SecureVault._();
  static const _keyName = 'pos.vault.aesgcm.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _key;
  Future<void> initialize() async {
    if (_key != null) return;
    var encoded = await _storage.read(key: _keyName);
    if (encoded == null) { encoded = base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256))); await _storage.write(key: _keyName, value: encoded); }
    _key = SecretKey(base64Url.decode(encoded));
  }
  Future<String> encrypt(String value, {String aad = 'pos'}) async {
    await initialize(); final box = await _cipher.encrypt(utf8.encode(value), secretKey: _key!, aad: utf8.encode(aad));
    return jsonEncode({'v': 1, 'n': base64UrlEncode(box.nonce), 'c': base64UrlEncode(box.cipherText), 'm': base64UrlEncode(box.mac.bytes)});
  }
  Future<String> decrypt(String payload, {String aad = 'pos'}) async {
    final j = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    await initialize(); final box = SecretBox(base64Url.decode(j['c'] as String), nonce: base64Url.decode(j['n'] as String), mac: Mac(base64Url.decode(j['m'] as String)));
    return utf8.decode(await _cipher.decrypt(box, secretKey: _key!, aad: utf8.encode(aad)));
  }
}

class SecurityManager extends ChangeNotifier {
  SecurityManager._(); static final instance = SecurityManager._();
  static const _usersKey = 'pos.security.users.v2', _auditKey = 'pos.security.audit.v2', _deviceKey = 'pos.security.device.v2', _auditSecretKey = 'pos.security.audit.secret.v1', _permissionsKey = 'pos.security.permissions.v1';
  static const _maxAuditEvents = 2000;

  /// Called after users or the audit log change locally so Wi-Fi sync can push
  /// the change to the other POS devices. Never called while applying a sync.
  VoidCallback? onSyncableChange;
  void _changed() => onSyncableChange?.call();
  final List<PosUser> _users = []; final List<AuditEvent> _audit = [];
  final Map<UserRole, Set<PosPermission>> _rolePermissions = {};
  SharedPreferences? _prefs; String _deviceId = ''; String _auditSecret = ''; PosUser? _user; bool _loaded = false, auditTampered = false;
  List<PosUser> get users => List.unmodifiable(_users); List<AuditEvent> get auditEvents => List.unmodifiable(_audit.reversed); PosUser? get currentUser => _user; String get deviceId => _deviceId; bool get initialized => _loaded; bool get needsOwnerSetup => _loaded && _users.isEmpty; bool get authenticated => _user != null;
  Future<void> initialize() async {
    if (_loaded) return; await SecureVault.instance.initialize(); _prefs = await SharedPreferences.getInstance();
    _deviceId = _prefs!.getString(_deviceKey) ?? _id('device'); await _prefs!.setString(_deviceKey, _deviceId);
    _auditSecret = await const FlutterSecureStorage().read(key: _auditSecretKey) ?? base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    await const FlutterSecureStorage().write(key: _auditSecretKey, value: _auditSecret);
    final rawUsers = _prefs!.getString(_usersKey), rawAudit = _prefs!.getString(_auditKey);
    if (rawUsers != null) _users.addAll((jsonDecode(rawUsers) as List).map((x) => PosUser.fromJson(Map<String, dynamic>.from(x as Map))));
    if (rawAudit != null) _audit.addAll((jsonDecode(rawAudit) as List).map((x) => AuditEvent.fromJson(Map<String, dynamic>.from(x as Map))));
    _loadRolePermissions();
    auditTampered = _audit.any((event) => event.signature.isEmpty || event.signature != _sign(event));
    _loaded = true; notifyListeners();
  }

  // ---- Wi-Fi sync integration -------------------------------------------
  // Users and the activity log travel inside the normal Wi-Fi sync snapshot as
  // two extra list sections. Audit signatures are per-device secrets, so they
  // are never sent; each device re-signs events it receives.

  Map<String, dynamic> syncSnapshot() => {
        'securityUsers': _users.map((u) => u.toJson()).toList(),
        'securityPermissions': _permissionsJson(),
        'securityAudit': _audit.map((e) {
          final j = e.toJson();
          j.remove('signature');
          j['at'] = e.at.toUtc().toIso8601String();
          return j;
        }).toList(),
      };

  bool _sameAuditContent(AuditEvent a, AuditEvent b) =>
      a.id == b.id && a.action == b.action && a.actor == b.actor && a.deviceId == b.deviceId && a.detail == b.detail && a.at.toUtc().isAtSameMomentAs(b.at.toUtc());

  Future<void> applySyncSnapshot(Map<String, dynamic> snapshot) async {
    if (!_loaded) return;
    final rawUsers = snapshot['securityUsers'];
    final rawAudit = snapshot['securityAudit'];
    final rawPermissions = snapshot['securityPermissions'];

    // Older peers do not send security data; an empty or owner-less user list
    // is ignored so a sync can never lock everyone out.
    if (rawUsers is List) {
      final incoming = rawUsers.whereType<Map>().map((x) => PosUser.fromJson(Map<String, dynamic>.from(x))).toList();
      if (incoming.any((u) => u.role == UserRole.owner && u.active)) {
        _users..clear()..addAll(incoming);
        await _persistUsers();
        final current = _user;
        if (current != null) {
          // Re-bind the signed-in user; a disabled/removed account is signed out.
          _user = _users.where((u) => u.id == current.id && u.active).firstOrNull;
        }
      }
    }

    if (rawPermissions is Map) {
      _applyRolePermissions(Map<String, dynamic>.from(rawPermissions));
      await _persistRolePermissions();
    }
    if (rawAudit is List) {
      final local = {for (final e in _audit) e.id: e};
      final merged = <AuditEvent>[];
      for (final raw in rawAudit.whereType<Map>()) {
        final j = Map<String, dynamic>.from(raw)..remove('signature');
        if (j['id'] is! String) continue;
        final event = AuditEvent.fromJson(j);
        final existing = local[event.id];
        if (existing != null && _sameAuditContent(existing, event)) {
          merged.add(existing);
        } else {
          event.signature = _sign(event);
          merged.add(event);
        }
      }
      merged.sort((a, b) => a.at.compareTo(b.at));
      if (merged.length > _maxAuditEvents) merged.removeRange(0, merged.length - _maxAuditEvents);
      _audit..clear()..addAll(merged);
      await _persistAudit();
      auditTampered = _audit.any((event) => event.signature.isEmpty || event.signature != _sign(event));
    }
    notifyListeners();
  }
  static String _id(String type) => '$type-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  String _sign(AuditEvent event) => crypto.Hmac(crypto.sha256, utf8.encode(_auditSecret)).convert(utf8.encode('${event.id}|${event.action}|${event.actor}|${event.deviceId}|${event.detail}|${event.at.toUtc().toIso8601String()}')).toString();
  String _pinHash(String pin, String salt) { var v = '$salt:$pin'; for (var i = 0; i < 120000; i++) { v = crypto.sha256.convert(utf8.encode(v)).toString(); } return v; }
  void _validatePin(String pin) { if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) throw StateError('PIN must be 4–12 digits.'); }
  Future<void> createOwner({required String name, required String pin}) async { if (_users.isNotEmpty) throw StateError('Owner account already exists.'); _validatePin(pin); final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256))); final user = PosUser(id: _id('user'), name: name.trim().isEmpty ? 'Owner' : name.trim(), username: 'owner', role: UserRole.owner, salt: salt, pinHash: _pinHash(pin, salt)); _users.add(user); _user = user; await _saveUsers(); await log('Owner account created'); notifyListeners(); }
  Future<bool> login(String username, String pin) async { final user = _users.where((x) => x.active && x.username.toLowerCase() == username.trim().toLowerCase()).firstOrNull; if (user == null || user.pinHash != _pinHash(pin, user.salt)) { await log('Failed sign in', detail: username.trim()); return false; } _user = user; await log('Signed in'); notifyListeners(); return true; }
  Future<void> logout() async { if (_user != null) await log('Signed out'); _user = null; notifyListeners(); }
  static const Map<UserRole, Set<PosPermission>> _defaultRolePermissions = {
    UserRole.admin: {PosPermission.sell, PosPermission.inventory, PosPermission.customers, PosPermission.reports, PosPermission.savedSaleChange, PosPermission.saleDelete, PosPermission.exportData, PosPermission.restoreBackup, PosPermission.users, PosPermission.security, PosPermission.device, PosPermission.branch},
    UserRole.manager: {PosPermission.sell, PosPermission.inventory, PosPermission.customers, PosPermission.reports},
    UserRole.cashier: {PosPermission.sell, PosPermission.customers},
  };
  Set<PosPermission> permissionsForRole(UserRole role) {
    if (role == UserRole.owner) return PosPermission.values.toSet();
    return Set.unmodifiable(_rolePermissions[role] ?? _defaultRolePermissions[role] ?? <PosPermission>{});
  }
  bool can(PosPermission permission) {
    final role = _user?.role;
    if (role == null) return false;
    return role == UserRole.owner || permissionsForRole(role).contains(permission);
  }
  Map<String, dynamic> _permissionsJson() => {
    for (final role in UserRole.values.where((r) => r != UserRole.owner))
      role.name: permissionsForRole(role).map((p) => p.name).toList(),
  };
  void _loadRolePermissions() {
    final raw = _prefs?.getString(_permissionsKey);
    if (raw != null) {
      try { _applyRolePermissions(Map<String, dynamic>.from(jsonDecode(raw) as Map)); return; } catch (_) {}
    }
    for (final role in UserRole.values.where((r) => r != UserRole.owner)) {
      _rolePermissions[role] = Set<PosPermission>.from(_defaultRolePermissions[role] ?? {});
    }
  }
  void _applyRolePermissions(Map<String, dynamic> raw) {
    for (final role in UserRole.values.where((r) => r != UserRole.owner)) {
      final values = raw[role.name];
      if (values is List) {
        _rolePermissions[role] = values.whereType<String>().map((name) =>
          PosPermission.values.where((p) => p.name == name).firstOrNull
        ).whereType<PosPermission>().toSet();
      } else {
        _rolePermissions[role] = Set<PosPermission>.from(_defaultRolePermissions[role] ?? {});
      }
    }
    // Keep management permissions restricted to Owner/Admin to avoid lockout.
    _rolePermissions[UserRole.manager]!.removeAll({PosPermission.users, PosPermission.security, PosPermission.device, PosPermission.branch, PosPermission.license});
    _rolePermissions[UserRole.cashier]!.removeAll({PosPermission.users, PosPermission.security, PosPermission.device, PosPermission.branch, PosPermission.license});
  }
  Future<void> setRolePermission(UserRole role, PosPermission permission, bool enabled) async {
    if (!can(PosPermission.security) || role == UserRole.owner) throw StateError('Only Owner or Admin can change role permissions.');
    if ({PosPermission.users, PosPermission.security, PosPermission.device, PosPermission.branch, PosPermission.license}.contains(permission) && role != UserRole.admin && enabled) {
      throw StateError('This permission is reserved for the Admin role.');
    }
    final set = _rolePermissions.putIfAbsent(role, () => Set<PosPermission>.from(_defaultRolePermissions[role] ?? {}));
    if (enabled) { set.add(permission); } else { set.remove(permission); }
    await _persistRolePermissions();
    await log('Role permissions changed', detail: '${role.label} • ${permission.name} • ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
  }
  Future<void> _persistRolePermissions() async {
    await _prefs!.setString(_permissionsKey, jsonEncode(_permissionsJson()));
    _changed();
  }
  Future<void> signUp({required String name, required String username, required String pin}) async {
    if (_users.isEmpty) {
      await createOwner(name: name, pin: pin);
      return;
    }
    _validatePin(pin);
    final userName = username.trim().toLowerCase();
    if (name.trim().isEmpty) throw StateError('Enter your name.');
    if (userName.length < 3 || _users.any((x) => x.username == userName)) throw StateError('Choose a unique username of at least 3 characters.');
    final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final user = PosUser(id: _id('user'), name: name.trim(), username: userName, role: UserRole.cashier, salt: salt, pinHash: _pinHash(pin, salt));
    _users.add(user);
    await _saveUsers();
    await log('Self sign-up created', detail: '$userName • Cashier');
    _user = user;
    notifyListeners();
  }
  Future<void> addUser({required String name, required String username, required UserRole role, required String pin}) async { if (!can(PosPermission.users)) throw StateError('Only Owner or Admin can add users.'); if (role == UserRole.owner) throw StateError('There can be only one Owner.'); _validatePin(pin); final userName = username.trim().toLowerCase(); if (userName.length < 3 || _users.any((x) => x.username == userName)) throw StateError('Choose a unique username of at least 3 characters.'); final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256))); _users.add(PosUser(id: _id('user'), name: name.trim(), username: userName, role: role, salt: salt, pinHash: _pinHash(pin, salt))); await _saveUsers(); await log('User created', detail: '$userName • ${role.label}'); notifyListeners(); }
  Future<void> setUserActive(PosUser user, bool active) async { if (!can(PosPermission.users) || user.role == UserRole.owner) throw StateError('This account cannot be changed.'); user.active = active; await _saveUsers(); await log(active ? 'User enabled' : 'User disabled', detail: user.username); notifyListeners(); }
  Future<void> log(String action, {String detail = ''}) async { final event = AuditEvent(id: _id('audit'), action: action, actor: _user?.username ?? 'System', deviceId: _deviceId, detail: detail, at: DateTime.now()); event.signature = _sign(event); _audit.add(event); if (_audit.length > _maxAuditEvents) _audit.removeRange(0, _audit.length - _maxAuditEvents); await _persistAudit(); _changed(); }
  Future<void> _persistAudit() => _prefs!.setString(_auditKey, jsonEncode(_audit.map((x) => x.toJson()).toList()));
  Future<bool> requireApproval(
    BuildContext context, {
    required PosPermission permission,
    required String action,
  }) async {
    if (can(permission)) return true;
    final pin = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(uiT('Approval required')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(uiF('{action} requires Owner or Admin approval.', {
              'action': uiT(action),
            })),
            const SizedBox(height: 12),
            TextField(
              controller: pin,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: uiT('Approver PIN'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(uiT('Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final ok = _users.any((x) =>
                  x.active &&
                  (x.role == UserRole.owner || x.role == UserRole.admin) &&
                  x.pinHash == _pinHash(pin.text, x.salt));
              Navigator.pop(ctx, ok);
            },
            child: Text(uiT('Approve')),
          ),
        ],
      ),
    );
    pin.dispose();
    if (approved == true) {
      await log('Sensitive action approved', detail: action);
    }
    return approved == true;
  }
  Future<void> _persistUsers() => _prefs!.setString(_usersKey, jsonEncode(_users.map((x) => x.toJson()).toList()));
  Future<void> _saveUsers() async { await _persistUsers(); _changed(); }
}

class SecurityGate extends StatelessWidget {
  const SecurityGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: SecurityManager.instance,
        builder: (context, _) {
          final s = SecurityManager.instance;
          if (!s.initialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (s.needsOwnerSetup) return const SignInScreen();
          return s.authenticated ? child : const SignInScreen();
        },
      );
}

class OwnerSetupScreen extends StatefulWidget {
  const OwnerSetupScreen({super.key});
  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  final name = TextEditingController();
  final pin = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'Set up the Owner account',
        subtitle: 'This protects users, sales, backups, and device access.',
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: uiT('Owner name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: uiT('Owner PIN (4–12 digits)'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: uiT('Confirm PIN'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    if (pin.text != confirm.text) {
                      setState(() => error = uiT('PINs do not match.'));
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await SecurityManager.instance.createOwner(
                        name: name.text,
                        pin: pin.text,
                      );
                    } catch (e) {
                      if (mounted) setState(() => error = uiError(e));
                    }
                    if (mounted) setState(() => busy = false);
                  },
            child: Text(uiT(busy ? 'Creating…' : 'Create Owner account')),
          ),
        ],
      );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final user = TextEditingController();
  final pin = TextEditingController();
  final name = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  bool busy = false;
  bool signingUp = false;

  @override
  void dispose() {
    user.dispose();
    pin.dispose();
    name.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: signingUp
            ? (SecurityManager.instance.needsOwnerSetup
                ? 'Create Owner account'
                : 'Create account')
            : 'Sign in to POS',
        subtitle: signingUp
            ? (SecurityManager.instance.needsOwnerSetup
                ? 'First account becomes Owner. Its username is fixed as owner.'
                : 'New accounts start with Cashier permissions.')
            : 'Use your assigned username and PIN. If this device has not synced yet, you can create a local account.',
        children: [
          if (signingUp)
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: uiT('Full name'),
                border: const OutlineInputBorder(),
              ),
            ),
          if (signingUp) const SizedBox(height: 10),
          if (!(signingUp && SecurityManager.instance.needsOwnerSetup))
            TextField(
              controller: user,
              autofocus: !signingUp,
              decoration: InputDecoration(
                labelText: uiT(
                  signingUp ? 'Username (3+ characters)' : 'Username',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => signingUp ? submitSignUp() : submit(),
            decoration: InputDecoration(
              labelText: uiT(signingUp ? 'PIN (4–12 digits)' : 'PIN'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (signingUp) const SizedBox(height: 10),
          if (signingUp)
            TextField(
              controller: confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: uiT('Confirm PIN'),
                border: const OutlineInputBorder(),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: busy ? null : (signingUp ? submitSignUp : submit),
            child: Text(uiT(busy
                ? 'Please wait…'
                : signingUp
                    ? 'Sign up'
                    : 'Sign in')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      signingUp = !signingUp;
                      error = null;
                    }),
            child: Text(uiT(signingUp
                ? 'Already have an account? Sign in'
                : 'New to this device? Sign up')),
          ),
        ],
      );

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await SecurityManager.instance.login(user.text, pin.text);
      if (mounted) {
        setState(() {
          busy = false;
          if (!ok) {
            error = uiT(
              'Incorrect username or PIN. If this device has not synced, use Sign up.',
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = uiError(e);
        });
      }
    }
  }

  Future<void> submitSignUp() async {
    if (pin.text != confirm.text) {
      setState(() => error = uiT('PINs do not match.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SecurityManager.instance.signUp(
        name: name.text,
        username: SecurityManager.instance.needsOwnerSetup ? 'owner' : user.text,
        pin: pin.text,
      );
    } catch (e) {
      if (mounted) setState(() => error = uiError(e));
    }
    if (mounted) setState(() => busy = false);
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 56,
                    color: Color(0xFF0F6E3F),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    uiT(title),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(uiT(subtitle), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
}

class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key, required this.wifiSync, this.onOpenWifiSync});
  final WifiSyncManager wifiSync;
  final VoidCallback? onOpenWifiSync;

  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  SecurityManager get s => SecurityManager.instance;

  Future<void> _addUser() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final pin = TextEditingController();
    var role = UserRole.cashier;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: Text(uiT('Add user')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: uiT('Name')),
              ),
              TextField(
                controller: username,
                decoration: InputDecoration(labelText: uiT('Username')),
              ),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: uiT('PIN')),
              ),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: InputDecoration(labelText: uiT('Role')),
                items: UserRole.values
                    .where((x) => x != UserRole.owner)
                    .map((x) => DropdownMenuItem(
                          value: x,
                          child: Text(uiT(x.label)),
                        ))
                    .toList(),
                onChanged: (x) => setDialog(() => role = x ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(uiT('Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await s.addUser(
                    name: name.text,
                    username: username.text,
                    role: role,
                    pin: pin.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(uiError(e))),
                    );
                  }
                }
              },
              child: Text(uiT('Add')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    username.dispose();
    pin.dispose();
  }

  Widget _permissionsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uiT('Role permissions'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(uiT(
                'Tap a role to expand its permissions. Choose which sections each role can access. Owner always retains full access.',
              )),
              for (final role in UserRole.values.where((r) => r != UserRole.owner)) ...[
                const Divider(height: 1),
                ExpansionTile(
                  key: PageStorageKey<String>('role-permissions-${role.name}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
                  title: Text(
                    uiT(role.label),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(uiF('{count} permissions enabled', {
                    'count': s.permissionsForRole(role).length.toString(),
                  })),
                  children: [
                    for (final permission in PosPermission.values)
                      if (!(role != UserRole.admin && {
                        PosPermission.users,
                        PosPermission.security,
                        PosPermission.device,
                        PosPermission.branch,
                        PosPermission.license,
                      }.contains(permission)))
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(uiT(_permissionLabel(permission))),
                          value: s.permissionsForRole(role).contains(permission),
                          onChanged: s.can(PosPermission.security)
                              ? (value) async {
                                  try {
                                    await s.setRolePermission(
                                      role,
                                      permission,
                                      value ?? false,
                                    );
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(uiError(e))),
                                      );
                                    }
                                  }
                                }
                              : null,
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  String _permissionLabel(PosPermission p) {
    switch (p) {
      case PosPermission.sell:
        return 'Sales';
      case PosPermission.inventory:
        return 'Inventory & incoming stock';
      case PosPermission.customers:
        return 'Customers & suppliers';
      case PosPermission.reports:
        return 'Reports';
      case PosPermission.savedSaleChange:
        return 'Edit saved sales';
      case PosPermission.saleDelete:
        return 'Delete sales';
      case PosPermission.exportData:
        return 'Export data';
      case PosPermission.restoreBackup:
        return 'Restore backups';
      case PosPermission.users:
        return 'Manage users';
      case PosPermission.security:
        return 'Security Center & role permissions';
      case PosPermission.device:
        return 'Device settings';
      case PosPermission.branch:
        return 'Branch settings';
      case PosPermission.license:
        return 'License settings';
    }
  }

  String _localizedAuditDetail(AuditEvent event) {
    final detail = event.detail;
    if (detail.isEmpty) return '';

    final permissionChange = RegExp(
      r'^(Owner|Admin|Manager|Cashier) • ([A-Za-z]+) • (enabled|disabled)$',
    ).firstMatch(detail);
    if (permissionChange != null) {
      final role = uiT(permissionChange.group(1)!);
      final permissionKey = switch (permissionChange.group(2)!) {
        'sell' => 'Sales',
        'inventory' => 'Inventory & incoming stock',
        'customers' => 'Customers & suppliers',
        'reports' => 'Reports',
        'savedSaleChange' => 'Edit saved sales',
        'saleDelete' => 'Delete sales',
        'exportData' => 'Export data',
        'restoreBackup' => 'Restore backups',
        'users' => 'Manage users',
        'security' => 'Security Center & role permissions',
        'device' => 'Device settings',
        'branch' => 'Branch settings',
        'license' => 'License settings',
        _ => permissionChange.group(2)!,
      };
      return '$role • ${uiT(permissionKey)} • ${uiT(permissionChange.group(3)!)}';
    }

    if (event.action == 'User created' || event.action == 'Self sign-up created') {
      final userRole = RegExp(r'^(.+) • (Owner|Admin|Manager|Cashier)$')
          .firstMatch(detail);
      if (userRole != null) {
        return '${userRole.group(1)} • ${uiT(userRole.group(2)!)}';
      }
    }

    // Some audit details are simple labels (for example, approved actions);
    // unknown or user-entered details are returned unchanged by uiT().
    return uiT(detail);
  }

  Widget _syncCard() => ValueListenableBuilder<WifiSyncViewState>(
        valueListenable: widget.wifiSync.status,
        builder: (context, st, _) {
          final mode = uiT(st.mode == WifiSyncMode.server
              ? 'Server'
              : st.mode == WifiSyncMode.client
                  ? 'Client'
                  : 'Off');
          final last = st.lastSync == null
              ? uiT('Never')
              : st.lastSync!.toLocal().toString().split('.').first;
          final pending = st.pending ? ' • ${uiT('changes pending')}' : '';

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wifi_tethering),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          uiF('Mode: {mode}', {'mode': mode}),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(uiT(
                    'Users, roles, PINs and the admin activity log sync over Wi-Fi with the rest of your POS data. No cloud server is used.',
                  )),
                  const SizedBox(height: 6),
                  Text(uiF('Last sync: {last}{pending}', {
                    'last': last,
                    'pending': pending,
                  })),
                  if (st.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        uiError(st.error),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.onOpenWifiSync != null)
                        OutlinedButton.icon(
                          onPressed: widget.onOpenWifiSync,
                          icon: const Icon(Icons.settings),
                          label: Text(uiT('Wi-Fi Sync settings')),
                        ),
                      if (st.mode == WifiSyncMode.client)
                        ElevatedButton.icon(
                          onPressed: st.busy
                              ? null
                              : () async {
                                  final r = await widget.wifiSync.syncNow();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(uiError(r.message))),
                                  );
                                },
                          icon: const Icon(Icons.sync),
                          label: Text(uiT('Sync now')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: s,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(uiT('Security Center')),
            backgroundColor: const Color(0xFF0F6E3F),
            foregroundColor: Colors.white,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(
                    '${s.currentUser?.name ?? ''} • ${uiT(s.currentUser?.role.label ?? '')}',
                  ),
                  subtitle: Text(uiF('Device {deviceId}', {'deviceId': s.deviceId})),
                  trailing: TextButton(
                    onPressed: s.logout,
                    child: Text(uiT('Sign out')),
                  ),
                ),
              ),
              if (s.auditTampered)
                Card(
                  color: const Color(0xFFFFE9E7),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    title: Text(uiT('Audit tampering detected')),
                    subtitle: Text(uiT(
                      'Restore a trusted backup and investigate this device.',
                    )),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                uiT('Users & roles'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (s.can(PosPermission.users))
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: _addUser,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(uiT('Add user')),
                  ),
                ),
              ...s.users.map((u) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(uiT(u.role.label).substring(0, 1)),
                      ),
                      title: Text('${u.name} • ${uiT(u.role.label)}'),
                      subtitle: Text(
                        '@${u.username}${u.active ? '' : ' • ${uiT('Disabled')}'}',
                      ),
                      trailing: s.can(PosPermission.users) && u.role != UserRole.owner
                          ? Switch(
                              value: u.active,
                              onChanged: (v) => s.setUserActive(u, v),
                            )
                          : null,
                    ),
                  )),
              if (s.can(PosPermission.security)) ...[
                const SizedBox(height: 16),
                _permissionsCard(),
              ],
              const SizedBox(height: 16),
              Text(
                uiT('Wi-Fi sync'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _syncCard(),
              const SizedBox(height: 16),
              Text(
                uiT('Admin activity log'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ...s.auditEvents.take(100).map((e) {
                final actor = uiT(e.actor);
                final detail = _localizedAuditDetail(e);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(uiT(e.action)),
                  subtitle: Text(
                    '$actor • ${e.at.toLocal()}${detail.isEmpty ? '' : '\n$detail'}',
                  ),
                );
              }),
            ],
          ),
        ),
      );
}
