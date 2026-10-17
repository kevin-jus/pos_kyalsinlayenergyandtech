import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wifi_sync.dart';

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
  static const _usersKey = 'pos.security.users.v2', _auditKey = 'pos.security.audit.v2', _deviceKey = 'pos.security.device.v2', _auditSecretKey = 'pos.security.audit.secret.v1';
  static const _maxAuditEvents = 2000;

  /// Called after users or the audit log change locally so Wi-Fi sync can push
  /// the change to the other POS devices. Never called while applying a sync.
  VoidCallback? onSyncableChange;
  void _changed() => onSyncableChange?.call();
  final List<PosUser> _users = []; final List<AuditEvent> _audit = [];
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
    auditTampered = _audit.any((event) => event.signature.isEmpty || event.signature != _sign(event));
    _loaded = true; notifyListeners();
  }

  // ---- Wi-Fi sync integration -------------------------------------------
  // Users and the activity log travel inside the normal Wi-Fi sync snapshot as
  // two extra list sections. Audit signatures are per-device secrets, so they
  // are never sent; each device re-signs events it receives.

  Map<String, dynamic> syncSnapshot() => {
        'securityUsers': _users.map((u) => u.toJson()).toList(),
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
  bool can(PosPermission permission) { final role = _user?.role; if (role == null) return false; if (role == UserRole.owner) return true; const admin = {PosPermission.sell, PosPermission.inventory, PosPermission.customers, PosPermission.reports, PosPermission.savedSaleChange, PosPermission.saleDelete, PosPermission.exportData, PosPermission.restoreBackup, PosPermission.users, PosPermission.security, PosPermission.device, PosPermission.branch}; const manager = {PosPermission.sell, PosPermission.inventory, PosPermission.customers, PosPermission.reports}; const cashier = {PosPermission.sell, PosPermission.customers}; return (role == UserRole.admin ? admin : role == UserRole.manager ? manager : cashier).contains(permission); }
  Future<void> addUser({required String name, required String username, required UserRole role, required String pin}) async { if (!can(PosPermission.users)) throw StateError('Only Owner or Admin can add users.'); if (role == UserRole.owner) throw StateError('There can be only one Owner.'); _validatePin(pin); final userName = username.trim().toLowerCase(); if (userName.length < 3 || _users.any((x) => x.username == userName)) throw StateError('Choose a unique username of at least 3 characters.'); final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256))); _users.add(PosUser(id: _id('user'), name: name.trim(), username: userName, role: role, salt: salt, pinHash: _pinHash(pin, salt))); await _saveUsers(); await log('User created', detail: '$userName • ${role.label}'); notifyListeners(); }
  Future<void> setUserActive(PosUser user, bool active) async { if (!can(PosPermission.users) || user.role == UserRole.owner) throw StateError('This account cannot be changed.'); user.active = active; await _saveUsers(); await log(active ? 'User enabled' : 'User disabled', detail: user.username); notifyListeners(); }
  Future<void> log(String action, {String detail = ''}) async { final event = AuditEvent(id: _id('audit'), action: action, actor: _user?.username ?? 'System', deviceId: _deviceId, detail: detail, at: DateTime.now()); event.signature = _sign(event); _audit.add(event); if (_audit.length > _maxAuditEvents) _audit.removeRange(0, _audit.length - _maxAuditEvents); await _persistAudit(); _changed(); }
  Future<void> _persistAudit() => _prefs!.setString(_auditKey, jsonEncode(_audit.map((x) => x.toJson()).toList()));
  Future<bool> requireApproval(BuildContext context, {required PosPermission permission, required String action}) async { if (can(permission)) return true; final pin = TextEditingController(); final approved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(title: const Text('Approval required'), content: Column(mainAxisSize: MainAxisSize.min, children: [Text('$action requires Owner or Admin approval.'), const SizedBox(height: 12), TextField(controller: pin, obscureText: true, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Approver PIN', border: OutlineInputBorder()))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () { final ok = _users.any((x) => x.active && (x.role == UserRole.owner || x.role == UserRole.admin) && x.pinHash == _pinHash(pin.text, x.salt)); Navigator.pop(ctx, ok); }, child: const Text('Approve'))])); pin.dispose(); if (approved == true) await log('Sensitive action approved', detail: action); return approved == true; }
  Future<void> _persistUsers() => _prefs!.setString(_usersKey, jsonEncode(_users.map((x) => x.toJson()).toList()));
  Future<void> _saveUsers() async { await _persistUsers(); _changed(); }
}

class SecurityGate extends StatelessWidget { const SecurityGate({super.key, required this.child}); final Widget child; @override Widget build(BuildContext context) => AnimatedBuilder(animation: SecurityManager.instance, builder: (context, _) { final s = SecurityManager.instance; if (!s.initialized) return const Scaffold(body: Center(child: CircularProgressIndicator())); if (s.needsOwnerSetup) return const OwnerSetupScreen(); return s.authenticated ? child : const SignInScreen(); }); }
class OwnerSetupScreen extends StatefulWidget { const OwnerSetupScreen({super.key}); @override State<OwnerSetupScreen> createState() => _OwnerSetupScreenState(); }
class _OwnerSetupScreenState extends State<OwnerSetupScreen> { final name = TextEditingController(), pin = TextEditingController(), confirm = TextEditingController(); String? error; bool busy = false; @override void dispose() { name.dispose(); pin.dispose(); confirm.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _AuthScaffold(title: 'Set up the Owner account', subtitle: 'This protects users, sales, backups, and device access.', children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Owner name', border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Owner PIN (4–12 digits)', border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: confirm, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm PIN', border: OutlineInputBorder())), if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))), const SizedBox(height: 16), ElevatedButton(onPressed: busy ? null : () async { if (pin.text != confirm.text) { setState(() => error = 'PINs do not match.'); return; } setState(() { busy = true; error = null; }); try { await SecurityManager.instance.createOwner(name: name.text, pin: pin.text); } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Bad state: ', '')); } if (mounted) setState(() => busy = false); }, child: Text(busy ? 'Creating…' : 'Create Owner account'))]); }
class SignInScreen extends StatefulWidget { const SignInScreen({super.key}); @override State<SignInScreen> createState() => _SignInScreenState(); }
class _SignInScreenState extends State<SignInScreen> { final user = TextEditingController(), pin = TextEditingController(); String? error; bool busy = false; @override void dispose() { user.dispose(); pin.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _AuthScaffold(title: 'Sign in to POS', subtitle: 'Use your assigned username and PIN.', children: [TextField(controller: user, autofocus: true, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, onSubmitted: (_) => submit(), decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder())), if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))), const SizedBox(height: 16), ElevatedButton(onPressed: busy ? null : submit, child: Text(busy ? 'Signing in…' : 'Sign in'))]); Future<void> submit() async { setState(() { busy = true; error = null; }); final ok = await SecurityManager.instance.login(user.text, pin.text); if (mounted) setState(() { busy = false; if (!ok) error = 'Incorrect username or PIN.'; }); } }
class _AuthScaffold extends StatelessWidget { const _AuthScaffold({required this.title, required this.subtitle, required this.children}); final String title, subtitle; final List<Widget> children; @override Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Icon(Icons.admin_panel_settings_outlined, size: 56, color: Color(0xFF0F6E3F)), const SizedBox(height: 12), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center), const SizedBox(height: 20), ...children]))))); }

class SecurityCenterPage extends StatefulWidget { const SecurityCenterPage({super.key, required this.wifiSync, this.onOpenWifiSync}); final WifiSyncManager wifiSync; final VoidCallback? onOpenWifiSync; @override State<SecurityCenterPage> createState() => _SecurityCenterPageState(); }
class _SecurityCenterPageState extends State<SecurityCenterPage> {
  SecurityManager get s => SecurityManager.instance;
  Future<void> _addUser() async { final name = TextEditingController(), username = TextEditingController(), pin = TextEditingController(); var role = UserRole.cashier; await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDialog) => AlertDialog(title: const Text('Add user'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')), TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN')), DropdownButtonFormField<UserRole>(initialValue: role, decoration: const InputDecoration(labelText: 'Role'), items: UserRole.values.where((x) => x != UserRole.owner).map((x) => DropdownMenuItem(value: x, child: Text(x.label))).toList(), onChanged: (x) => setDialog(() => role = x ?? role))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: () async { try { await s.addUser(name: name.text, username: username.text, role: role, pin: pin.text); if (ctx.mounted) Navigator.pop(ctx); } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', '')))); } }, child: const Text('Add'))]))); name.dispose(); username.dispose(); pin.dispose(); }
  Widget _syncCard() => ValueListenableBuilder<WifiSyncViewState>(valueListenable: widget.wifiSync.status, builder: (context, st, _) {
    final mode = st.mode == WifiSyncMode.server ? 'Server' : st.mode == WifiSyncMode.client ? 'Client' : 'Off';
    final last = st.lastSync == null ? 'Never' : st.lastSync!.toLocal().toString().split('.').first;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.wifi_tethering), const SizedBox(width: 8), Expanded(child: Text('Mode: $mode', style: const TextStyle(fontWeight: FontWeight.w600)))]),
      const SizedBox(height: 6),
      const Text('Users, roles, PINs and the admin activity log sync over Wi-Fi with the rest of your POS data. No cloud server is used.'),
      const SizedBox(height: 6), Text('Last sync: $last${st.pending ? ' • changes pending' : ''}'),
      if (st.error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(st.error, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        if (widget.onOpenWifiSync != null) OutlinedButton.icon(onPressed: widget.onOpenWifiSync, icon: const Icon(Icons.settings), label: const Text('Wi-Fi Sync settings')),
        if (st.mode == WifiSyncMode.client) ElevatedButton.icon(onPressed: st.busy ? null : () async { final r = await widget.wifiSync.syncNow(); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message))); }, icon: const Icon(Icons.sync), label: const Text('Sync now')),
      ]),
    ])));
  });
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: s, builder: (context, _) => Scaffold(appBar: AppBar(title: const Text('Security Center'), backgroundColor: const Color(0xFF0F6E3F), foregroundColor: Colors.white), body: ListView(padding: const EdgeInsets.all(16), children: [Card(child: ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text('${s.currentUser?.name} • ${s.currentUser?.role.label}'), subtitle: Text('Device ${s.deviceId}'), trailing: TextButton(onPressed: s.logout, child: const Text('Sign out')))), if (s.auditTampered) const Card(color: Color(0xFFFFE9E7), child: ListTile(leading: Icon(Icons.warning_amber_rounded, color: Colors.red), title: Text('Audit tampering detected'), subtitle: Text('Restore a trusted backup and investigate this device.'))), const SizedBox(height: 16), const Text('Users & roles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), if (s.can(PosPermission.users)) Align(alignment: Alignment.centerLeft, child: ElevatedButton.icon(onPressed: _addUser, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add user'))), ...s.users.map((u) => Card(child: ListTile(leading: CircleAvatar(child: Text(u.role.label.substring(0, 1))), title: Text('${u.name} • ${u.role.label}'), subtitle: Text('@${u.username}${u.active ? '' : ' • Disabled'}'), trailing: s.can(PosPermission.users) && u.role != UserRole.owner ? Switch(value: u.active, onChanged: (v) => s.setUserActive(u, v)) : null))), const SizedBox(height: 16), const Text('Wi-Fi sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), _syncCard(), const SizedBox(height: 16), const Text('Admin activity log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ...s.auditEvents.take(100).map((e) => ListTile(dense: true, leading: const Icon(Icons.history), title: Text(e.action), subtitle: Text('${e.actor} • ${e.at.toLocal()}${e.detail.isEmpty ? '' : '\n${e.detail}'}')))])));
}
