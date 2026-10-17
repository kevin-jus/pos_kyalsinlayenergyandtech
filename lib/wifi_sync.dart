import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

const int _wifiSyncProtocolVersion = 1;
const int _defaultSyncPort = 8765;
const int _discoveryPort = 8766;
const int _maxJsonBytes = 50 * 1024 * 1024;

class WifiSyncViewState {
  const WifiSyncViewState({
    this.mode = WifiSyncMode.off,
    this.serverRunning = false,
    this.clientConnected = false,
    this.busy = false,
    this.pending = false,
    this.message = '',
    this.error = '',
    this.conflicts = 0,
    this.lastSync,
    this.knownClients = 0,
  });

  final WifiSyncMode mode;
  final bool serverRunning;
  final bool clientConnected;
  final bool busy;
  final bool pending;
  final String message;
  final String error;
  final int conflicts;
  final DateTime? lastSync;
  final int knownClients;

  WifiSyncViewState copyWith({
    WifiSyncMode? mode,
    bool? serverRunning,
    bool? clientConnected,
    bool? busy,
    bool? pending,
    String? message,
    String? error,
    int? conflicts,
    DateTime? lastSync,
    bool clearLastSync = false,
    int? knownClients,
  }) {
    return WifiSyncViewState(
      mode: mode ?? this.mode,
      serverRunning: serverRunning ?? this.serverRunning,
      clientConnected: clientConnected ?? this.clientConnected,
      busy: busy ?? this.busy,
      pending: pending ?? this.pending,
      message: message ?? this.message,
      error: error ?? this.error,
      conflicts: conflicts ?? this.conflicts,
      lastSync: clearLastSync ? null : (lastSync ?? this.lastSync),
      knownClients: knownClients ?? this.knownClients,
    );
  }
}

enum WifiSyncMode { off, server, client }

class WifiDiscoveredServer {
  const WifiDiscoveredServer({
    required this.host,
    required this.port,
    required this.serverId,
    required this.name,
  });

  final String host;
  final int port;
  final String serverId;
  final String name;

  @override
  String toString() => '$name @ $host:$port';
}

class WifiPairPreview {
  const WifiPairPreview({
    required this.snapshot,
    required this.serverId,
    required this.host,
    required this.port,
    required this.name,
  });

  final Map<String, dynamic> snapshot;
  final String serverId;
  final String host;
  final int port;
  final String name;
}

class WifiSyncResult {
  const WifiSyncResult({
    required this.success,
    required this.message,
    this.conflicts = const [],
    this.serverSnapshot,
  });

  final bool success;
  final String message;
  final List<String> conflicts;
  final Map<String, dynamic>? serverSnapshot;
}

class WifiSyncManager with WidgetsBindingObserver {
  WifiSyncManager({
    required this.readLocalSnapshot,
    required this.applyRemoteSnapshot,
    required this.getLocalUserRevision,
  });

  final Future<Map<String, dynamic>> Function() readLocalSnapshot;
  final Future<void> Function(Map<String, dynamic> snapshot)
      applyRemoteSnapshot;
  final Future<int> Function() getLocalUserRevision;

  static const String _stateFileName = 'pos_wifi_sync_state.json';

  final ValueNotifier<WifiSyncViewState> status =
      ValueNotifier(const WifiSyncViewState());

  Timer? _autoTimer;
  Timer? _debounceTimer;
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Future<void> _serverSyncChain = Future<void>.value();
  bool _syncBusy = false;
  bool _syncAgain = false;
  bool _initialized = false;

  WifiSyncMode mode = WifiSyncMode.off;
  bool autoSync = true;

  String deviceId = '';
  String serverId = '';
  String serverToken = '';
  String serverName = 'Kyal Sin Lay POS';
  int serverPort = _defaultSyncPort;

  String clientHost = '';
  int clientPort = _defaultSyncPort;
  String clientToken = '';
  String clientServerId = '';
  Map<String, dynamic>? baseSnapshot;

  final Map<String, DateTime> _knownClients = <String, DateTime>{};

  bool get serverRunning => _server != null;
  bool get clientConfigured =>
      clientToken.trim().isNotEmpty &&
      (clientHost.trim().isNotEmpty || clientServerId.trim().isNotEmpty);
  bool get hasBaseSnapshot => baseSnapshot != null;
  int get knownClientCount => _knownClients.length;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      await _loadState();
      if (deviceId.isEmpty) {
        deviceId = _randomId('dev');
        await _saveState();
      }

      if (mode == WifiSyncMode.server) {
        await enableServer(port: serverPort, persist: false);
      } else if (mode == WifiSyncMode.client) {
        _startAutoTimer();
        if (autoSync && clientConfigured && baseSnapshot != null) {
          unawaited(syncNow(silent: true));
        }
      } else {
        _setStatus(status.value.copyWith(mode: WifiSyncMode.off));
      }
    } catch (e) {
      _setStatus(
        status.value.copyWith(
          error: 'Wi-Fi sync initialization failed: $e',
          message: 'Wi-Fi sync is available, but could not start automatically.',
        ),
      );
    }
  }

  Future<void> disable() async {
    await _stopServer();
    _stopAutoTimer();
    mode = WifiSyncMode.off;
    // Keep the saved client pairing/base snapshot so turning sync off and on
    // does not force a needless re-pair.
    await _saveState();
    _setStatus(
      const WifiSyncViewState(mode: WifiSyncMode.off, message: 'Wi-Fi sync is off.'),
    );
  }

  Future<void> enableServer({int? port, bool persist = true}) async {
    await _stopServer();
    _stopAutoTimer();

    mode = WifiSyncMode.server;
    serverPort = port ?? serverPort;
    if (serverPort < 1024 || serverPort > 65535) {
      throw StateError('Wi-Fi server port must be between 1024 and 65535.');
    }
    if (serverId.isEmpty) serverId = _randomId('srv');
    if (serverToken.isEmpty) serverToken = _randomToken();

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        serverPort,
        shared: false,
      );
      _server!.listen(
        _handleHttpRequest,
        onError: (Object error, StackTrace stack) {
          _setStatus(
            status.value.copyWith(error: 'Wi-Fi server error: $error'),
          );
          debugPrint('Wi-Fi HTTP server error: $error');
          debugPrintStack(stackTrace: stack);
        },
      );

      await _startDiscoveryListener();

      if (persist) await _saveState();
      _setStatus(
        status.value.copyWith(
          mode: WifiSyncMode.server,
          serverRunning: true,
          clientConnected: false,
          busy: false,
          pending: false,
          error: '',
          message: 'Wi-Fi server is running on port $serverPort.',
          knownClients: _knownClients.length,
        ),
      );
    } catch (e) {
      await _stopServer();
      mode = WifiSyncMode.off;
      _setStatus(
        status.value.copyWith(
          mode: WifiSyncMode.off,
          serverRunning: false,
          error: 'Could not start Wi-Fi server: $e',
          message: 'Try another port or close the other app using this port.',
        ),
      );
      if (persist) await _saveState();
      rethrow;
    }
  }

  Future<void> enableClient({bool persist = true}) async {
    await _stopServer();
    mode = WifiSyncMode.client;
    _startAutoTimer();
    if (persist) await _saveState();
    _setStatus(
      status.value.copyWith(
        mode: WifiSyncMode.client,
        serverRunning: false,
        clientConnected: false,
        busy: false,
        pending: baseSnapshot == null,
        error: '',
        message: baseSnapshot == null
            ? 'Client mode is ready. Enter the server connection code or server IP.'
            : 'Client mode is ready. Automatic synchronization will reconnect when the server is reachable.',
      ),
    );
  }

  Future<void> configureClient({
    required String host,
    required int port,
    required String token,
    String serverId = '',
  }) async {
    _validateClientSettings(host: host, port: port, token: token);
    final normalizedHost = _normalizeHost(host);
    final normalizedToken = token.trim();
    final normalizedServerId = serverId.trim();
    final sameConnection =
        mode == WifiSyncMode.client &&
        clientHost == normalizedHost &&
        clientPort == port &&
        clientToken == normalizedToken &&
        (normalizedServerId.isEmpty || clientServerId == normalizedServerId);

    await _stopServer();
    mode = WifiSyncMode.client;
    clientHost = normalizedHost;
    clientPort = port;
    clientToken = normalizedToken;
    clientServerId = normalizedServerId.isEmpty ? clientServerId : normalizedServerId;
    if (!sameConnection) baseSnapshot = null;
    await _saveState();
    _startAutoTimer();
    _setStatus(
      status.value.copyWith(
        mode: WifiSyncMode.client,
        serverRunning: false,
        clientConnected: false,
        busy: false,
        pending: true,
        error: '',
        message: 'Client connection saved. Pair once to begin synchronization.',
      ),
    );
  }

  Future<void> configureClientFromCode(String code) async {
    final parsed = parseConnectionCode(code);
    if (parsed == null) {
      throw const FormatException(
        'Connection code is invalid. Expected POSSYNC1|IP|PORT|TOKEN|SERVER_ID.',
      );
    }
    await configureClient(
      host: parsed.host,
      port: parsed.port,
      token: parsed.token,
      serverId: parsed.serverId,
    );
  }

  Future<WifiPairPreview> pairPreview() async {
    if (mode != WifiSyncMode.client) {
      throw StateError('Enable Client mode before pairing.');
    }
    await _ensureClientHost();

    try {
      final response = await _postJson(
        clientHost,
        clientPort,
        '/sync',
        <String, dynamic>{
          'protocol': _wifiSyncProtocolVersion,
          'operation': 'pair',
          'token': clientToken,
          'deviceId': deviceId,
        },
      );
      _checkResponse(response);
      final snapshot = _mapFrom(response['snapshot']);
      final remoteServerId = response['serverId']?.toString() ?? '';
      final remoteName = response['name']?.toString() ?? 'POS Server';
      if (remoteServerId.isEmpty) {
        throw StateError('Server did not return a valid server ID.');
      }

      clientServerId = remoteServerId;
      // Keep the address that actually answered the request. A server may have
      // multiple network interfaces, and its first enumerated interface is not
      // necessarily the one reachable from this client.
      clientPort = _intValue(response['port'], clientPort);
      await _saveState();
      _setStatus(
        status.value.copyWith(
          clientConnected: true,
          error: '',
          message: 'Server found. Review the data before first pairing.',
        ),
      );
      return WifiPairPreview(
        snapshot: snapshot,
        serverId: remoteServerId,
        host: clientHost,
        port: clientPort,
        name: remoteName,
      );
    } catch (e) {
      final discovered = await _discoverMatchingServer();
      if (discovered == null) {
        _setStatus(
          status.value.copyWith(
            clientConnected: false,
            error: 'Could not reach the POS server: $e',
            message: 'Check that both devices are on the same Wi-Fi network.',
          ),
        );
        rethrow;
      }
      clientHost = discovered.host;
      clientPort = discovered.port;
      clientServerId = discovered.serverId;
      await _saveState();
      final response = await _postJson(
        clientHost,
        clientPort,
        '/sync',
        <String, dynamic>{
          'protocol': _wifiSyncProtocolVersion,
          'operation': 'pair',
          'token': clientToken,
          'deviceId': deviceId,
        },
      );
      _checkResponse(response);
      final snapshot = _mapFrom(response['snapshot']);
      _setStatus(
        status.value.copyWith(
          clientConnected: true,
          error: '',
          message: 'Server found automatically over Wi-Fi.',
        ),
      );
      return WifiPairPreview(
        snapshot: snapshot,
        serverId: response['serverId']?.toString() ?? clientServerId,
        host: clientHost,
        port: clientPort,
        name: response['name']?.toString() ?? discovered.name,
      );
    }
  }

  Future<void> acceptInitialServerSnapshot(WifiPairPreview preview) async {
    await applyRemoteSnapshot(preview.snapshot);
    clientServerId = preview.serverId;
    clientHost = preview.host;
    clientPort = preview.port;
    baseSnapshot = _deepMap(preview.snapshot);
    mode = WifiSyncMode.client;
    autoSync = true;
    await _saveState();
    _setStatus(
      status.value.copyWith(
        mode: WifiSyncMode.client,
        clientConnected: true,
        pending: false,
        error: '',
        conflicts: 0,
        lastSync: DateTime.now(),
        message: 'Initial pairing complete. Automatic synchronization is enabled.',
      ),
    );
    _startAutoTimer();
  }

  Future<WifiSyncResult> syncNow({bool silent = false}) async {
    if (mode != WifiSyncMode.client) {
      return const WifiSyncResult(
        success: false,
        message: 'Wi-Fi client mode is not enabled.',
      );
    }
    if (!clientConfigured) {
      return const WifiSyncResult(
        success: false,
        message: 'Connect this device to a POS server first.',
      );
    }
    if (baseSnapshot == null) {
      return const WifiSyncResult(
        success: false,
        message: 'Initial pairing is required before automatic sync can start.',
      );
    }

    if (_syncBusy) {
      _syncAgain = true;
      return const WifiSyncResult(
        success: false,
        message: 'A synchronization is already running.',
      );
    }

    _syncBusy = true;
    _setStatus(
      status.value.copyWith(
        busy: true,
        error: '',
        message: silent ? status.value.message : 'Synchronizing over Wi-Fi…',
      ),
    );

    WifiSyncResult result;
    try {
      result = await _syncClientOnce();
    } catch (e) {
      _setStatus(
        status.value.copyWith(
          busy: false,
          clientConnected: false,
          pending: true,
          error: '$e',
          message: 'Sync will retry automatically when the server is reachable.',
        ),
      );
      result = WifiSyncResult(success: false, message: '$e');
    } finally {
      _syncBusy = false;
    }

    if (_syncAgain) {
      _syncAgain = false;
      if (mode == WifiSyncMode.client && autoSync) {
        unawaited(syncNow(silent: true));
      }
    }
    return result;
  }

  Future<void> setAutoSync(bool enabled) async {
    autoSync = enabled;
    await _saveState();
    if (mode == WifiSyncMode.client && enabled) {
      _startAutoTimer();
      if (baseSnapshot != null) unawaited(syncNow(silent: true));
    } else if (!enabled) {
      _debounceTimer?.cancel();
    }
    _setStatus(status.value.copyWith(pending: enabled ? status.value.pending : false));
  }

  void notifyLocalDataChanged() {
    if (!_initialized || mode != WifiSyncMode.client || !autoSync) return;
    _setStatus(status.value.copyWith(pending: true));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(syncNow(silent: true));
    });
  }

  Future<List<WifiDiscoveredServer>> discoverServers() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final found = <String, WifiDiscoveredServer>{};
    final done = Completer<void>();
    Timer(const Duration(milliseconds: 1400), () {
      if (!done.isCompleted) done.complete();
    });

    void sendDiscovery() {
      final payload = utf8.encode(
        'POS_DISCOVER|${clientServerId.isEmpty ? '*' : clientServerId}',
      );
      socket.send(payload, InternetAddress('255.255.255.255'), _discoveryPort);
    }

    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final d = datagram!;
        final parts = utf8.decode(d.data, allowMalformed: true).split('|');
        if (parts.length < 4 || parts[0] != 'POS_SERVER') continue;
        final actualServerId = parts[1].trim();
        final port = int.tryParse(parts[2].trim()) ?? _defaultSyncPort;
        final name = parts.sublist(3).join('|').trim();
        final host = d.address.address;
        final key = '$actualServerId@$host:$port';
        if (actualServerId.isNotEmpty) {
          found[key] = WifiDiscoveredServer(
            host: host,
            port: port,
            serverId: actualServerId,
            name: name.isEmpty ? 'POS Server' : name,
          );
        }
      }
    });

    sendDiscovery();
    await done.future;
    socket.close();

    return found.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
  }

  Future<List<String>> localIpv4Addresses() async {
    final addresses = <String>[];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (!address.isLoopback && !addresses.contains(address.address)) {
          addresses.add(address.address);
        }
      }
    }
    addresses.sort();
    return addresses;
  }

  String connectionCodeFor(String host) {
    return 'POSSYNC1|${_normalizeHost(host)}|$serverPort|$serverToken|$serverId';
  }

  static ({String host, int port, String token, String serverId})?
      parseConnectionCode(String code) {
    final cleaned = code.trim();
    if (cleaned.startsWith('POSSYNC1|')) {
      final parts = cleaned.split('|');
      if (parts.length != 5) return null;
      final port = int.tryParse(parts[2]);
      if (port == null || parts[1].trim().isEmpty || parts[3].trim().isEmpty) {
        return null;
      }
      return (
        host: parts[1].trim(),
        port: port,
        token: parts[3].trim(),
        serverId: parts[4].trim(),
      );
    }

    try {
      final uri = Uri.parse(cleaned);
      if (uri.scheme.toLowerCase() != 'possync') return null;
      final host = uri.queryParameters['host'] ?? '';
      final port = int.tryParse(uri.queryParameters['port'] ?? '');
      final token = uri.queryParameters['token'] ?? '';
      final serverId = uri.queryParameters['serverId'] ?? '';
      if (host.isEmpty || port == null || token.isEmpty) return null;
      return (
        host: host,
        port: port,
        token: token,
        serverId: serverId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mode == WifiSyncMode.client &&
        autoSync &&
        hasBaseSnapshot) {
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> _syncClientDisposeState() async {
    await _stopServer();
    _stopAutoTimer();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<WifiSyncResult> _syncClientOnce() async {
    final startRevision = await getLocalUserRevision();
    await _ensureClientHost();
    final local = await readLocalSnapshot();
    final base = baseSnapshot!;

    Map<String, dynamic> response;
    try {
      response = await _postJson(
        clientHost,
        clientPort,
        '/sync',
        <String, dynamic>{
          'protocol': _wifiSyncProtocolVersion,
          'operation': 'sync',
          'token': clientToken,
          'deviceId': deviceId,
          'base': base,
          'local': local,
        },
      );
    } catch (_) {
      final discovered = await _discoverMatchingServer();
      if (discovered == null) rethrow;
      clientHost = discovered.host;
      clientPort = discovered.port;
      clientServerId = discovered.serverId;
      await _saveState();
      response = await _postJson(
        clientHost,
        clientPort,
        '/sync',
        <String, dynamic>{
          'protocol': _wifiSyncProtocolVersion,
          'operation': 'sync',
          'token': clientToken,
          'deviceId': deviceId,
          'base': base,
          'local': local,
        },
      );
    }

    _checkResponse(response);
    final merged = _mapFrom(response['snapshot']);
    final conflicts = (response['conflicts'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    // A POS transaction may have been saved locally while the HTTP request was
    // in flight. Re-sync from the new local state rather than overwriting it.
    final endRevision = await getLocalUserRevision();
    if (endRevision != startRevision) {
      final freshLocal = await readLocalSnapshot();
      final retryResponse = await _postJson(
        clientHost,
        clientPort,
        '/sync',
        <String, dynamic>{
          'protocol': _wifiSyncProtocolVersion,
          'operation': 'sync',
          'token': clientToken,
          'deviceId': deviceId,
          'base': baseSnapshot!,
          'local': freshLocal,
        },
      );
      _checkResponse(retryResponse);
      final retryMerged = _mapFrom(retryResponse['snapshot']);
      final retryConflicts = (retryResponse['conflicts'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      await applyRemoteSnapshot(retryMerged);
      baseSnapshot = _deepMap(retryMerged);
      await _saveState();
      _setStatus(
        status.value.copyWith(
          mode: WifiSyncMode.client,
          clientConnected: true,
          busy: false,
          pending: false,
          error: '',
          conflicts: retryConflicts.length,
          lastSync: DateTime.now(),
          message: retryConflicts.isEmpty
              ? 'Sync complete.'
              : 'Sync complete. ${retryConflicts.length} conflict(s) were resolved on the server.',
        ),
      );
      return WifiSyncResult(
        success: true,
        message: 'Sync complete.',
        conflicts: retryConflicts,
        serverSnapshot: retryMerged,
      );
    }

    await applyRemoteSnapshot(merged);
    baseSnapshot = _deepMap(merged);
    clientServerId = response['serverId']?.toString() ?? clientServerId;
    // Keep the host that successfully handled this request.
    clientPort = _intValue(response['port'], clientPort);
    await _saveState();

    _setStatus(
      status.value.copyWith(
        mode: WifiSyncMode.client,
        clientConnected: true,
        busy: false,
        pending: false,
        error: '',
        conflicts: conflicts.length,
        lastSync: DateTime.now(),
        message: conflicts.isEmpty
            ? 'Sync complete.'
            : 'Sync complete. ${conflicts.length} conflict(s) were resolved on the server.',
      ),
    );

    return WifiSyncResult(
      success: true,
      message: 'Sync complete.',
      conflicts: conflicts,
      serverSnapshot: merged,
    );
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.headers.set('access-control-allow-origin', '*');
    response.headers.set('access-control-allow-headers', 'Content-Type');
    response.headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');

    try {
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }

      if (request.uri.path == '/hello' && request.method == 'GET') {
        final addresses = await localIpv4Addresses();
        await _writeJson(response, <String, dynamic>{
          'ok': true,
          'protocol': _wifiSyncProtocolVersion,
          'serverId': serverId,
          'name': serverName,
          'port': serverPort,
          'addresses': addresses,
        });
        return;
      }

      if (request.uri.path != '/sync' || request.method != 'POST') {
        response.statusCode = HttpStatus.notFound;
        await _writeJson(response, <String, dynamic>{
          'ok': false,
          'error': 'Unknown endpoint.',
        });
        return;
      }

      final body = await _readJsonBody(request);
      if (_intValue(body['protocol'], -1) != _wifiSyncProtocolVersion) {
        throw StateError('Unsupported Wi-Fi sync protocol version.');
      }
      final token = body['token']?.toString() ?? '';
      if (token.isEmpty || token != serverToken) {
        response.statusCode = HttpStatus.unauthorized;
        await _writeJson(response, <String, dynamic>{
          'ok': false,
          'error': 'Invalid pairing token.',
        });
        return;
      }

      final device = body['deviceId']?.toString() ?? '';
      if (device.isNotEmpty) {
        _knownClients[device] = DateTime.now();
        _setStatus(status.value.copyWith(knownClients: _knownClients.length));
      }

      final operation = body['operation']?.toString() ?? 'sync';
      if (operation == 'pair') {
        final current = await readLocalSnapshot();
        final addresses = await localIpv4Addresses();
        await _writeJson(response, <String, dynamic>{
          'ok': true,
          'protocol': _wifiSyncProtocolVersion,
          'serverId': serverId,
          'name': serverName,
          'port': serverPort,
          'host': addresses.isEmpty ? '' : addresses.first,
          'snapshot': current,
        });
        return;
      }

      if (operation != 'sync') {
        throw StateError('Unknown sync operation.');
      }

      final base = _mapFromNullable(body['base']);
      final local = _mapFrom(body['local']);

      // Serialize server merges with one another. The main AppData persistence
      // layer additionally serializes actual SQLite replacements with ordinary
      // POS writes.
      final operationFuture = _serverSyncChain.then((_) async {
        final startRevision = await getLocalUserRevision();
        var current = await readLocalSnapshot();
        MergeResult merged = mergeSnapshots(
          base: base,
          local: local,
          remote: current,
        );

        final revisionAfterMerge = await getLocalUserRevision();
        if (revisionAfterMerge != startRevision) {
          current = await readLocalSnapshot();
          merged = mergeSnapshots(
            base: base,
            local: local,
            remote: current,
          );
        }

        if (!snapshotsEqual(current, merged.snapshot)) {
          await applyRemoteSnapshot(merged.snapshot);
        }

        final addresses = await localIpv4Addresses();
        return <String, dynamic>{
          'ok': true,
          'protocol': _wifiSyncProtocolVersion,
          'serverId': serverId,
          'name': serverName,
          'port': serverPort,
          'host': addresses.isEmpty ? '' : addresses.first,
          'snapshot': merged.snapshot,
          'conflicts': merged.conflicts,
        };
      });

      _serverSyncChain = operationFuture.then<void>((_) {}, onError: (_) {});
      final result = await operationFuture;
      await _writeJson(response, result);
      return;
    } catch (e, stack) {
      debugPrint('Wi-Fi request failed: $e');
      debugPrintStack(stackTrace: stack);
      response.statusCode = HttpStatus.badRequest;
      await _writeJson(response, <String, dynamic>{
        'ok': false,
        'error': '$e',
      });
    }
  }

  Future<void> _startDiscoveryListener() async {
    _discoverySocket?.close();
    _discoverySocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
    );
    _discoverySocket!.broadcastEnabled = true;
    _discoverySocket!.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = _discoverySocket!.receive()) != null) {
        final d = datagram!;
        final parts = utf8.decode(d.data, allowMalformed: true).split('|');
        if (parts.length < 2 || parts[0] != 'POS_DISCOVER') continue;
        final wanted = parts[1].trim();
        if (wanted != '*' && wanted != serverId) continue;
        final payload = utf8.encode(
          'POS_SERVER|$serverId|$serverPort|$serverName',
        );
        _discoverySocket!.send(payload, d.address, d.port);
      }
    });
  }

  Future<WifiDiscoveredServer?> _discoverMatchingServer() async {
    final discovered = await discoverServers();
    final servers = <WifiDiscoveredServer>[...discovered];

    // Some Android routers/APs filter UDP broadcasts between Wi-Fi clients.
    // Fall back to a small TCP scan of the local IPv4 subnet and ask each
    // candidate for /hello. This is only used when broadcast discovery found
    // nothing, so normal discovery stays fast.
    if (servers.isEmpty) {
      servers.addAll(await _scanLocalSubnets());
    }

    if (servers.isEmpty) return null;
    if (clientServerId.isEmpty) return servers.first;
    for (final server in servers) {
      if (server.serverId == clientServerId) return server;
    }
    return null;
  }

  Future<List<WifiDiscoveredServer>> _scanLocalSubnets() async {
    final localAddresses = await localIpv4Addresses();
    final candidateHosts = <String>{};

    for (final address in localAddresses) {
      final parts = address.split('.');
      if (parts.length != 4) continue;
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a == null || b == null || c == null) continue;
      final privateSubnet = a == 10 ||
          (a == 192 && b == 168) ||
          (a == 172 && b >= 16 && b <= 31);
      if (!privateSubnet) continue;
      for (var host = 1; host <= 254; host++) {
        final candidate = '$a.$b.$c.$host';
        if (candidate != address) candidateHosts.add(candidate);
      }
    }

    final found = <String, WifiDiscoveredServer>{};
    final hosts = candidateHosts.toList();
    const batchSize = 32;
    for (var i = 0; i < hosts.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, hosts.length).toInt();
      final batch = hosts.sublist(i, end);
      final results = await Future.wait(
        batch.map(_probeServerHost),
      );
      for (final server in results) {
        if (server == null) continue;
        found['${server.serverId}@${server.host}:${server.port}'] = server;
      }
      if (clientServerId.isNotEmpty &&
          found.values.any((s) => s.serverId == clientServerId)) {
        break;
      }
    }
    return found.values.toList();
  }

  Future<WifiDiscoveredServer?> _probeServerHost(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 350)
      ..idleTimeout = const Duration(milliseconds: 500);
    try {
      final request = await client
          .get(host, _defaultSyncPort, '/hello')
          .timeout(const Duration(milliseconds: 600));
      final response = await request.close().timeout(
        const Duration(milliseconds: 900),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final raw = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map || decoded['ok'] != true) return null;
      final server = WifiDiscoveredServer(
        host: host,
        port: _intValue(decoded['port'], _defaultSyncPort),
        serverId: decoded['serverId']?.toString() ?? '',
        name: decoded['name']?.toString() ?? 'POS Server',
      );
      if (server.serverId.isEmpty) return null;
      return server;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureClientHost() async {
    if (clientHost.trim().isNotEmpty) return;
    final discovered = await _discoverMatchingServer();
    if (discovered == null) {
      throw StateError('The POS server could not be discovered on this Wi-Fi network.');
    }
    clientHost = discovered.host;
    clientPort = discovered.port;
    clientServerId = discovered.serverId;
    await _saveState();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mode == WifiSyncMode.client && autoSync && hasBaseSnapshot) {
        unawaited(syncNow(silent: true));
      }
    });
  }

  void _stopAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    final discovery = _discoverySocket;
    _discoverySocket = null;
    discovery?.close();
  }

  Future<void> _loadState() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_stateFileName');
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);

    deviceId = map['deviceId']?.toString() ?? '';
    serverId = map['serverId']?.toString() ?? '';
    serverToken = map['serverToken']?.toString() ?? '';
    serverName = map['serverName']?.toString() ?? 'Kyal Sin Lay POS';
    serverPort = _intValue(map['serverPort'], _defaultSyncPort);
    clientHost = _normalizeHost(map['clientHost']?.toString() ?? '');
    clientPort = _intValue(map['clientPort'], _defaultSyncPort);
    clientToken = map['clientToken']?.toString() ?? '';
    clientServerId = map['clientServerId']?.toString() ?? '';
    autoSync = map['autoSync'] as bool? ?? true;

    final rawBase = map['baseSnapshot'];
    baseSnapshot = rawBase is Map ? _deepMap(Map<String, dynamic>.from(rawBase)) : null;

    final rawMode = map['mode']?.toString() ?? 'off';
    mode = switch (rawMode) {
      'server' => WifiSyncMode.server,
      'client' => WifiSyncMode.client,
      _ => WifiSyncMode.off,
    };

    final rawClients = map['knownClients'];
    if (rawClients is Map) {
      for (final entry in rawClients.entries) {
        final parsed = DateTime.tryParse(entry.value?.toString() ?? '');
        if (parsed != null && entry.key.toString().isNotEmpty) {
          _knownClients[entry.key.toString()] = parsed;
        }
      }
    }

    final rawLastSync = map['lastSync']?.toString();
    final lastSync = DateTime.tryParse(rawLastSync ?? '');
    _setStatus(
      status.value.copyWith(
        mode: mode,
        serverRunning: false,
        clientConnected: false,
        pending: mode == WifiSyncMode.client && baseSnapshot == null,
        lastSync: lastSync,
        knownClients: _knownClients.length,
      ),
    );
  }

  Future<void> _saveState() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$_stateFileName');
    final temp = File('${file.path}.tmp');
    final payload = <String, dynamic>{
      'version': 1,
      'mode': _modeName(mode),
      'deviceId': deviceId,
      'serverId': serverId,
      'serverToken': serverToken,
      'serverName': serverName,
      'serverPort': serverPort,
      'clientHost': clientHost,
      'clientPort': clientPort,
      'clientToken': clientToken,
      'clientServerId': clientServerId,
      'autoSync': autoSync,
      'baseSnapshot': baseSnapshot,
      'knownClients': _knownClients.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
      'lastSync': status.value.lastSync?.toIso8601String(),
    };
    await temp.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<Map<String, dynamic>> _postJson(
    String host,
    int port,
    String path,
    Map<String, dynamic> body,
  ) async {
    final normalizedHost = _normalizeHost(host);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    client.idleTimeout = const Duration(seconds: 15);
    try {
      final request = await client.post(normalizedHost, port, path).timeout(
        const Duration(seconds: 6),
      );
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(body));
      if (bytes.length > _maxJsonBytes) {
        throw StateError('Sync payload is too large.');
      }
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final responseBytes = await response.fold<List<int>>(<int>[], (a, b) {
        if (a.length + b.length > _maxJsonBytes) {
          throw StateError('Sync response is too large.');
        }
        a.addAll(b);
        return a;
      });
      final raw = utf8.decode(responseBytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw StateError('POS server returned an invalid response.');
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  void _checkResponse(Map<String, dynamic> response) {
    if (response['ok'] != true) {
      throw StateError(response['error']?.toString() ?? 'POS server rejected the request.');
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(<int>[], (a, b) {
      if (a.length + b.length > _maxJsonBytes) {
        throw StateError('Request is too large.');
      }
      a.addAll(b);
      return a;
    });
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Sync request must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _writeJson(HttpResponse response, Map<String, dynamic> value) async {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > _maxJsonBytes) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode(<String, dynamic>{
        'ok': false,
        'error': 'Response is too large for Wi-Fi sync.',
      }));
    } else {
      response.contentLength = bytes.length;
      response.add(bytes);
    }
    await response.close();
  }

  void _setStatus(WifiSyncViewState next) {
    status.value = next;
  }

  void _validateClientSettings({
    required String host,
    required int port,
    required String token,
  }) {
    if (_normalizeHost(host).isEmpty) {
      throw StateError('Server IP address cannot be empty.');
    }
    if (port < 1024 || port > 65535) {
      throw StateError('Server port must be between 1024 and 65535.');
    }
    if (token.trim().length < 16) {
      throw StateError('Pairing token is too short. Copy the complete token from the server.');
    }
  }

  static String _normalizeHost(String host) {
    var value = host.trim();
    if (value.startsWith('http://')) value = value.substring(7);
    if (value.startsWith('https://')) value = value.substring(8);
    if (value.contains('/')) value = value.split('/').first;
    return value.trim();
  }

  static String _modeName(WifiSyncMode value) => switch (value) {
        WifiSyncMode.off => 'off',
        WifiSyncMode.server => 'server',
        WifiSyncMode.client => 'client',
      };

  static int _intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _randomId(String prefix) {
    final random = Random.secure();
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final extra = List.generate(10, (_) => random.nextInt(36).toRadixString(36)).join();
    return '$prefix-$time-$extra';
  }

  static String _randomToken() {
    final random = Random.secure();
    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    return List.generate(40, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is! Map) throw const FormatException('Expected a JSON object.');
    return Map<String, dynamic>.from(value);
  }

  static Map<String, dynamic>? _mapFromNullable(dynamic value) {
    if (value == null) return null;
    return _mapFrom(value);
  }

  static Map<String, dynamic> _deepMap(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
  }


  Future<void> dispose() async {
    await _syncClientDisposeState();
    status.dispose();
  }
}

class MergeResult {
  const MergeResult({required this.snapshot, required this.conflicts});

  final Map<String, dynamic> snapshot;
  final List<String> conflicts;
}

MergeResult mergeSnapshots({
  required Map<String, dynamic>? base,
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) {
  // A missing base is deliberately treated as a pairing operation by the UI,
  // not as an implicit merge. Blindly summing two unrelated stock snapshots
  // could double-count inventory. Normal automatic sync always has a base.
  if (base == null) {
    return MergeResult(snapshot: _cloneMap(remote), conflicts: const []);
  }

  final conflicts = <String>[];
  final adjustedLocal = _cloneMap(local);
  _renameOfflineVoucherCollisions(
    base: base,
    local: adjustedLocal,
    remote: remote,
    conflicts: conflicts,
  );

  final merged = <String, dynamic>{};
  final allKeys = <String>{...base.keys, ...adjustedLocal.keys, ...remote.keys};

  for (final key in allKeys) {
    final baseValue = base[key];
    final localValue = adjustedLocal[key];
    final remoteValue = remote[key];

    if (_isListSection(key)) {
      final result = _mergeListSection(
        section: key,
        baseValue: baseValue,
        localValue: localValue,
        remoteValue: remoteValue,
        conflicts: conflicts,
      );
      merged[key] = result;
      continue;
    }

    merged[key] = _mergeValue(
      path: key,
      base: baseValue,
      local: localValue,
      remote: remoteValue,
      conflicts: conflicts,
    );
  }

  _reconcileMergedProductMetadata(merged);
  return MergeResult(snapshot: merged, conflicts: conflicts);
}

void _reconcileMergedProductMetadata(Map<String, dynamic> snapshot) {
  final products = snapshot['products'];
  final supplies = snapshot['incomingSupplies'];
  if (products is! List || supplies is! List) return;

  final suppliesByProduct = <String, List<Map<String, dynamic>>>{};
  for (final raw in supplies) {
    if (raw is! Map) continue;
    final supply = Map<String, dynamic>.from(raw);
    final productId = supply['productId']?.toString() ?? '';
    if (productId.isEmpty) continue;
    suppliesByProduct.putIfAbsent(productId, () => []).add(supply);
  }

  for (var i = 0; i < products.length; i++) {
    final raw = products[i];
    if (raw is! Map) continue;
    final product = Map<String, dynamic>.from(raw);
    final productId = product['id']?.toString() ?? '';
    final related = suppliesByProduct[productId];
    if (productId.isEmpty || related == null || related.isEmpty) continue;

    related.sort((a, b) => _dateSortKey(b['date']).compareTo(_dateSortKey(a['date'])));
    final latest = related.first;
    final latestDate = latest['date']?.toString() ?? '';
    if (latestDate.isNotEmpty) product['lastIncomingDate'] = latestDate;

    final incomingCost = _numValue(latest['costPerUnit']);
    final type = (product['type']?.toString() ?? '').trim().toLowerCase();
    final subtractsParent = product['subtractFromParentStock'] == true;
    if (incomingCost != null && !subtractsParent) {
      if (type == 'lpg') {
        final conversion = _numValue(product['saleStockUnitsPerUnit']) ?? 1.0;
        product['cost'] = incomingCost * (conversion > 0 ? conversion : 1.0);
      } else {
        product['cost'] = incomingCost;
      }
    }

    for (final supply in related) {
      final supplier = supply['supplier']?.toString().trim() ?? '';
      if (supplier.isNotEmpty) {
        product['supplier'] = supplier;
        break;
      }
    }
    products[i] = product;
  }
}

double _dateSortKey(String value) {
  final date = DateTime.tryParse(value);
  return (date ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch.toDouble();
}

double? _numValue(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

void _renameOfflineVoucherCollisions({
  required Map<String, dynamic> base,
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required List<String> conflicts,
}) {
  final baseSales = _salesByVoucher(base['sales']);
  final localSales = _salesByVoucher(local['sales']);
  final remoteSales = _salesByVoucher(remote['sales']);
  final used = <String>{...baseSales.keys, ...localSales.keys, ...remoteSales.keys};
  final renames = <String, String>{};

  for (final voucher in localSales.keys.toList()..sort()) {
    final l = localSales[voucher];
    final r = remoteSales[voucher];
    if (l == null || r == null || baseSales.containsKey(voucher)) continue;
    if (_canonicalJson(l) == _canonicalJson(r)) continue;

    final newVoucher = _newVoucherForConflict(voucher, used);
    renames[voucher] = newVoucher;
    conflicts.add(
      'Sales voucher $voucher was created independently on both devices; local sale was renumbered to $newVoucher.',
    );
  }

  if (renames.isEmpty) return;

  final sales = local['sales'];
  if (sales is List) {
    local['sales'] = sales.map((raw) {
      if (raw is! Map) return raw;
      final item = Map<String, dynamic>.from(raw);
      final old = item['voucherNumber']?.toString() ?? '';
      final replacement = renames[old];
      if (replacement != null) item['voucherNumber'] = replacement;
      return item;
    }).toList();
  }

  final saleItems = local['saleItems'];
  if (saleItems is List) {
    local['saleItems'] = saleItems.map((raw) {
      if (raw is! Map) return raw;
      final item = Map<String, dynamic>.from(raw);
      final old = item['saleVoucherNumber']?.toString() ?? '';
      final replacement = renames[old];
      if (replacement != null) item['saleVoucherNumber'] = replacement;
      return item;
    }).toList();
  }

  final payments = local['paymentTransactions'];
  if (payments is List) {
    local['paymentTransactions'] = payments.map((raw) {
      if (raw is! Map) return raw;
      final item = Map<String, dynamic>.from(raw);
      if ((item['linkedType']?.toString() ?? '') == 'sale') {
        final old = item['linkedId']?.toString() ?? '';
        final replacement = renames[old];
        if (replacement != null) item['linkedId'] = replacement;
      }
      return item;
    }).toList();
  }
}

Map<String, dynamic> _salesByVoucher(dynamic value) {
  final result = <String, dynamic>{};
  if (value is! List) return result;
  for (var i = 0; i < value.length; i++) {
    final raw = value[i];
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final voucher = map['voucherNumber']?.toString().trim() ?? '';
    if (voucher.isNotEmpty) result[voucher] = map;
  }
  return result;
}


bool snapshotsEqual(Map<String, dynamic> a, Map<String, dynamic> b) =>
    _canonicalJson(a) == _canonicalJson(b);

bool _isListSection(String key) => const {
      'products',
      'people',
      'sales',
      'saleItems',
      'incomingSupplies',
      'paymentTransactions',
      'expenses',
      'incomeExpense',
      'cylinderRows',
      'cylinderTypes',
      'cylinderCycles',
      'securityUsers',
      'securityAudit',
    }.contains(key);

Object _mergeListSection({
  required String section,
  required dynamic baseValue,
  required dynamic localValue,
  required dynamic remoteValue,
  required List<String> conflicts,
}) {
  final baseList = baseValue is List ? baseValue : const <dynamic>[];
  final localList = localValue is List ? localValue : const <dynamic>[];
  final remoteList = remoteValue is List ? remoteValue : const <dynamic>[];

  if (section == 'sales') {
    return _mergeSalesSection(
      baseList: baseList,
      localList: localList,
      remoteList: remoteList,
      conflicts: conflicts,
    );
  }

  final keyer = _keyerForSection(section);
  final baseMap = _indexList(baseList, keyer);
  final localMap = _indexList(localList, keyer);
  final remoteMap = _indexList(remoteList, keyer);
  final keys = <String>{...baseMap.keys, ...localMap.keys, ...remoteMap.keys};
  final result = <dynamic>[];

  final sortedKeys = keys.toList()..sort();
  for (final itemKey in sortedKeys) {
    final b = baseMap[itemKey];
    final l = localMap[itemKey];
    final r = remoteMap[itemKey];
    final merged = _mergeRecord(
      section: section,
      key: itemKey,
      base: b,
      local: l,
      remote: r,
      conflicts: conflicts,
    );
    if (merged != null) result.add(merged);
  }
  return result;
}

Object _mergeSalesSection({
  required List baseList,
  required List localList,
  required List remoteList,
  required List<String> conflicts,
}) {
  final baseMap = _indexList(baseList, (item, index) => _recordKey('sales', item, index));
  final localMap = _indexList(localList, (item, index) => _recordKey('sales', item, index));
  final remoteMap = _indexList(remoteList, (item, index) => _recordKey('sales', item, index));
  final allKeys = <String>{...baseMap.keys, ...remoteMap.keys, ...localMap.keys};
  final result = <dynamic>[];

  for (final key in (allKeys.toList()..sort())) {
    final merged = _mergeRecord(
      section: 'sales',
      key: key,
      base: baseMap[key],
      local: localMap[key],
      remote: remoteMap[key],
      conflicts: conflicts,
    );
    if (merged != null) result.add(merged);
  }
  return result;
}


String _newVoucherForConflict(String original, Set<String> used) {
  final pattern = RegExp(r'^V-(\d+)$');
  final match = pattern.firstMatch(original);
  var n = match == null
      ? (DateTime.now().millisecondsSinceEpoch % 1000000)
      : int.tryParse(match.group(1) ?? '') ?? 0;
  if (n < 1) n = 1;
  while (true) {
    n++;
    final candidate = 'V-${n.toString().padLeft(6, '0')}';
    if (!used.contains(candidate)) {
      used.add(candidate);
      return candidate;
    }
  }
}

Map<String, dynamic>? _mergeRecord({
  required String section,
  required String key,
  required dynamic base,
  required dynamic local,
  required dynamic remote,
  required List<String> conflicts,
}) {
  if (base == null && local == null && remote == null) return null;
  if (base == null) {
    if (local == null) return _cloneRecord(remote);
    if (remote == null) return _cloneRecord(local);
    if (_canonicalJson(local) == _canonicalJson(remote)) return _cloneRecord(local);
    conflicts.add('$section/$key was created differently on both devices; server copy was kept.');
    return _cloneRecord(remote);
  }

  if (local == null && remote == null) return null;
  if (local == null) {
    if (_canonicalJson(base) == _canonicalJson(remote)) return null;
    conflicts.add('$section/$key was deleted locally but changed on the server; server copy was kept.');
    return _cloneRecord(remote);
  }
  if (remote == null) {
    if (_canonicalJson(base) == _canonicalJson(local)) return null;
    conflicts.add('$section/$key was deleted on the server but changed locally; server copy was kept.');
    return _cloneRecord(remote);
  }

  return _mergeValue(
    path: '$section/$key',
    base: base,
    local: local,
    remote: remote,
    conflicts: conflicts,
  ) as Map<String, dynamic>?;
}

Object? _mergeValue({
  required String path,
  required dynamic base,
  required dynamic local,
  required dynamic remote,
  required List<String> conflicts,
}) {
  if (_canonicalJson(local) == _canonicalJson(base)) return _cloneAny(remote);
  if (_canonicalJson(remote) == _canonicalJson(base)) return _cloneAny(local);
  if (_canonicalJson(local) == _canonicalJson(remote)) return _cloneAny(local);

  if (local is Map && remote is Map && base is Map) {
    final keys = <String>{
      ...base.keys.map((e) => e.toString()),
      ...local.keys.map((e) => e.toString()),
      ...remote.keys.map((e) => e.toString()),
    };
    final result = <String, dynamic>{};
    for (final key in keys) {
      final merged = _mergeValue(
        path: '$path.$key',
        base: base[key],
        local: local[key],
        remote: remote[key],
        conflicts: conflicts,
      );
      if (merged != null || local.containsKey(key) || remote.containsKey(key)) {
        result[key] = merged;
      }
    }
    return result;
  }

  // Stock is derived from independent sales/receipts and should accumulate
  // offline changes from both devices relative to the common base snapshot.
  if (path.endsWith('/stock') && _isNumber(local) && _isNumber(remote) && _isNumber(base)) {
    final merged = _number(base) +
        (_number(local) - _number(base)) +
        (_number(remote) - _number(base));
    if (merged < -0.000001) {
      conflicts.add('$path received concurrent offline stock deductions beyond the shared stock; stock was clamped to 0. Review the affected vouchers.');
      return 0.0;
    }
    return merged < 0 ? 0.0 : merged;
  }

  // Cylinder quantities follow the same additive-delta rule because cycle
  // changes can happen independently on two offline devices.
  if (path.endsWith('/totalQuantity') &&
      _isNumber(local) &&
      _isNumber(remote) &&
      _isNumber(base)) {
    final merged = _number(base) +
        (_number(local) - _number(base)) +
        (_number(remote) - _number(base));
    if (merged < -0.000001) {
      conflicts.add('$path received concurrent offline cylinder changes beyond available stock; quantity was clamped to 0. Review the cylinder cycles.');
      return 0.0;
    }
    return merged < 0 ? 0.0 : merged;
  }

  conflicts.add('$path changed on both devices; server copy was kept.');
  return _cloneAny(remote);
}

Map<String, dynamic> _indexList(
  List list,
  String Function(dynamic item, int index) keyer,
) {
  final result = <String, dynamic>{};
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    final key = keyer(item, i);
    if (key.isEmpty) {
      result['__index_$i'] = item;
    } else {
      result[key] = item;
    }
  }
  return result;
}

String Function(dynamic item, int index) _keyerForSection(String section) {
  return (dynamic item, int index) => _recordKey(section, item, index);
}

String _recordKey(String section, dynamic item, int index) {
  if (item is! Map) return '__index_$index';
  final j = Map<String, dynamic>.from(item);
  switch (section) {
    case 'products':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'people':
      return '${j['category'] ?? ''}|${j['name'] ?? ''}'.toString().toLowerCase();
    case 'sales':
      return j['voucherNumber']?.toString().trim() ?? '__index_$index';
    case 'saleItems':
      return '${j['saleVoucherNumber'] ?? ''}|${j['productId'] ?? ''}|${j['saleUnit'] ?? ''}|${j['quantity'] ?? ''}|${j['sellingPrice'] ?? ''}';
    case 'incomingSupplies':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'paymentTransactions':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'expenses':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'incomeExpense':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'cylinderRows':
      return j['no']?.toString() ?? '__index_$index';
    case 'cylinderTypes':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'securityUsers':
    case 'securityAudit':
      return j['id']?.toString().trim() ?? '__index_$index';
    case 'cylinderCycles':
      return j['id']?.toString().trim() ?? '__index_$index';
    default:
      return '__index_$index';
  }
}

Map<String, dynamic>? _cloneRecord(dynamic value) {
  if (value == null) return null;
  if (value is! Map) return null;
  return _cloneMap(Map<String, dynamic>.from(value));
}

Map<String, dynamic> _cloneMap(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

Object? _cloneAny(Object? value) {
  if (value == null) return null;
  return jsonDecode(jsonEncode(value));
}

String _canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final entries = <String, Object?>{};
      final keys = input.keys.map((e) => e.toString()).toList()..sort();
      for (final key in keys) {
        entries[key] = normalize(input[key]);
      }
      return entries;
    }
    if (input is List) return input.map(normalize).toList();
    return input;
  }

  return jsonEncode(normalize(value));
}

bool _isNumber(Object? value) => value is num;
double _number(Object? value) => (value as num).toDouble();
