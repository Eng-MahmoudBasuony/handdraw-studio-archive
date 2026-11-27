import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'codex_rpc_client.dart';

/// Talks only to the user-installed, loopback development host. The endpoint's
/// random capability token is local to this macOS account and is never logged.
final class CodexDevelopmentRpc implements CodexRpc {
  CodexDevelopmentRpc(this.endpoint);
  final File endpoint;
  Socket? _socket;
  Future<void>? _connecting;
  StreamSubscription<String>? _subscription;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  late final _requests = CodexRpcRequests(
    send: (message) {
      final socket = _socket;
      if (socket == null) throw const CodexFailure('developmentUnavailable');
      socket.writeln(jsonEncode(message));
    },
    stop: close,
  );
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> connect() => _connecting ??= _connect();

  Future<void> _connect() async {
    try {
      final config = jsonDecode(await endpoint.readAsString()) as Map;
      final port = config['port'];
      final token = config['token'];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          token is! String ||
          token.length < 32) {
        throw const CodexFailure('developmentUnavailable');
      }
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 5),
      );
      _socket = socket;
      _subscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_line, onError: (_) => _lost(), onDone: _lost);
      socket.writeln(jsonEncode({'token': token}));
      await request('initialize', {
        'clientInfo': {
          'name': 'handdraw_studio',
          'version': AppBuildInfo.version,
        },
        'capabilities': {'experimentalApi': false},
      });
      socket.writeln(
        jsonEncode({'method': 'initialized', 'params': <String, dynamic>{}}),
      );
    } catch (_) {
      await close();
      throw const CodexFailure('developmentUnavailable');
    }
  }

  void _line(String line) {
    try {
      final value = jsonDecode(line) as Map<String, dynamic>;
      final id = value['id'];
      if (value.containsKey('method')) {
        if (id != null) {
          // Full-access commands run in the host. Interactive permissions,
          // external messages and other client actions are never auto-granted.
          _socket?.writeln(
            jsonEncode({
              'id': id,
              'error': {
                'code': -32601,
                'message': 'Unsupported client request',
              },
            }),
          );
        } else {
          _events.add(value);
        }
      } else if (id is int) {
        _requests.receive(value);
      }
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _socket?.destroy();
    _socket = null;
    _connecting = null;
    _requests.disconnect('connectionLost');
    _events.add({'method': 'handdraw/disconnected'});
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    return _requests.request(
      method,
      params,
      timeout: Duration(seconds: method == 'thread/start' ? 120 : 30),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _lost();
  }
}
