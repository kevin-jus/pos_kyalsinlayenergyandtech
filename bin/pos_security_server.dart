// Run with: POS_SERVER_ADMIN_TOKEN=change-me dart run bin/pos_security_server.dart
// A small, dependency-free companion service for licenses, branches, devices,
// encrypted backup envelopes, and update metadata. Put it behind HTTPS in
// production and keep POS_SERVER_ADMIN_TOKEN outside source control.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final String adminToken = Platform.environment['POS_SERVER_ADMIN_TOKEN'] ?? '';
final File store = File(Platform.environment['POS_SERVER_DATA'] ?? 'pos_security_server.json');

Future<Map<String, dynamic>> readStore() async {
  if (!await store.exists()) return {'branches': <String, dynamic>{}, 'backups': <String, dynamic>{}, 'update': <String, dynamic>{}};
  return Map<String, dynamic>.from(jsonDecode(await store.readAsString()) as Map);
}
Future<void> saveStore(Map<String, dynamic> value) async => store.writeAsString(jsonEncode(value));
Future<Map<String, dynamic>> body(HttpRequest request) async => Map<String, dynamic>.from(jsonDecode(await utf8.decoder.bind(request).join()) as Map);
String bearer(HttpRequest r) => r.headers.value(HttpHeaders.authorizationHeader)?.replaceFirst('Bearer ', '') ?? '';
Future<void> reply(HttpRequest r, int code, Map<String, dynamic> data) async { r.response.statusCode = code; r.response.headers.contentType = ContentType.json; r.response.write(jsonEncode(data)); await r.response.close(); }
bool admin(HttpRequest r) => adminToken.isNotEmpty && bearer(r) == adminToken;
Map<String, dynamic>? branch(Map<String, dynamic> db, HttpRequest r, String id) { final value = (db['branches'] as Map)[id]; if (value is! Map || value['apiToken'] != bearer(r)) return null; return Map<String, dynamic>.from(value); }

Future<void> main() async {
  if (adminToken.isEmpty) { stderr.writeln('Set POS_SERVER_ADMIN_TOKEN before starting the server.'); exitCode = 64; return; }
  final server = await HttpServer.bind(InternetAddress.anyIPv4, int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080);
  stdout.writeln('POS security server listening on ${server.address.address}:${server.port}');
  await for (final request in server) {
    try {
      final path = request.uri.path; final db = await readStore(); final branches = Map<String, dynamic>.from(db['branches'] as Map);
      if (request.method == 'POST' && path == '/v1/admin/branches') {
        if (!admin(request)) { await reply(request, 401, {'error': 'admin authorization required'}); continue; }
        final b = await body(request); final id = b['branchId']?.toString().trim() ?? ''; final token = b['apiToken']?.toString().trim() ?? '';
        if (id.isEmpty || token.length < 24) { await reply(request, 400, {'error': 'branchId and a 24+ character apiToken are required'}); continue; }
        branches[id] = {'apiToken': token, 'active': b['active'] != false, 'authorizedDevices': <String>[], 'updatedAt': DateTime.now().toUtc().toIso8601String()}; db['branches'] = branches; await saveStore(db); await reply(request, 201, {'branchId': id}); continue;
      }
      if (request.method == 'POST' && path == '/v1/admin/devices') {
        if (!admin(request)) { await reply(request, 401, {'error': 'admin authorization required'}); continue; }
        final b = await body(request); final id = b['branchId']?.toString() ?? ''; final device = b['deviceId']?.toString() ?? ''; final record = branches[id];
        if (record is! Map || device.isEmpty) { await reply(request, 404, {'error': 'branch or device not found'}); continue; }
        final list = List<String>.from(record['authorizedDevices'] as List? ?? const []); if (!list.contains(device)) list.add(device); record['authorizedDevices'] = list; branches[id] = record; db['branches'] = branches; await saveStore(db); await reply(request, 200, {'authorized': true}); continue;
      }
      if (request.method == 'POST' && path == '/v1/license/validate') {
        final b = await body(request); final id = b['branchId']?.toString() ?? ''; final device = b['deviceId']?.toString() ?? ''; final record = branch(db, request, id);
        if (record == null) { await reply(request, 401, {'active': false}); continue; }
        final devices = List<String>.from(record['authorizedDevices'] as List? ?? const []); final active = record['active'] == true && devices.contains(device);
        await reply(request, active ? 200 : 403, {'active': active, 'branchId': id, 'deviceAuthorized': devices.contains(device)}); continue;
      }
      if (request.method == 'POST' && path == '/v1/backups') {
        final b = await body(request); final id = b['branchId']?.toString() ?? ''; final record = branch(db, request, id); final payload = b['payload'];
        if (record == null) { await reply(request, 401, {'error': 'unauthorized'}); continue; }
        if (payload is! String || payload.length > 60 * 1024 * 1024) { await reply(request, 400, {'error': 'invalid encrypted backup'}); continue; }
        final backups = Map<String, dynamic>.from(db['backups'] as Map); backups[id] = {'payload': payload, 'deviceId': b['deviceId'], 'createdAt': DateTime.now().toUtc().toIso8601String()}; db['backups'] = backups; await saveStore(db); await reply(request, 201, {'stored': true}); continue;
      }
      if (request.method == 'GET' && path == '/v1/backups/latest') {
        final id = request.uri.queryParameters['branchId'] ?? ''; if (branch(db, request, id) == null) { await reply(request, 401, {'error': 'unauthorized'}); continue; }
        final value = (db['backups'] as Map)[id]; if (value is! Map) { await reply(request, 404, {'error': 'no backup'}); continue; } await reply(request, 200, Map<String, dynamic>.from(value)); continue;
      }
      if (request.method == 'GET' && path == '/v1/updates/latest') { await reply(request, 200, Map<String, dynamic>.from(db['update'] as Map)); continue; }
      await reply(request, 404, {'error': 'not found'});
    } catch (e) { await reply(request, 500, {'error': 'server error'}); }
  }
}
