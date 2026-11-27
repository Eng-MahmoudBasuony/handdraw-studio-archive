import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class CodexRpc {
  Stream<Map<String, dynamic>> get events;
  Future<void> connect();
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  );
  Future<void> close();
}

/// A dedicated Codex process, config, and login owned by HandDraw. Never reads
/// the desktop client's auth files or inherits an API key/provider override.
class CodexRpcClient implements CodexRpc {
  CodexRpcClient({required this.home, this.executable});
  final Directory home;
  final String? executable;
  Process? _process;
  Future<void>? _connecting;
  late final _requests = CodexRpcRequests(send: _send, stop: close);
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> connect() => _connecting ??= _start();

  Future<void> _start() async {
    await home.create(recursive: true);
    final candidates = [
      ?executable,
      '/Applications/ChatGPT.app/Contents/Resources/codex',
      '/Applications/Codex.app/Contents/Resources/codex',
      '/opt/homebrew/bin/codex',
      '/usr/local/bin/codex',
    ];
    String? binary;
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        binary = candidate;
        break;
      }
    }
    if (binary == null) {
      _connecting = null;
      throw const CodexFailure('codexMissing');
    }
    final environment = Map<String, String>.from(Platform.environment)
      ..removeWhere(
        (key, _) => key.startsWith('OPENAI_') || key.startsWith('CODEX_'),
      );
    environment['CODEX_HOME'] = home.path;
    try {
      final process = await Process.start(
        binary,
        [
          '-c',
          'forced_login_method="chatgpt"',
          '-c',
          'cli_auth_credentials_store="file"',
          '-c',
          'model_provider="openai"',
          '-c',
          'web_search="disabled"',
          for (final feature in [
            'shell_tool',
            'unified_exec',
            'code_mode_host',
            'apps',
            'browser_use',
            'computer_use',
            'image_generation',
            'multi_agent',
            'hooks',
            'skill_search',
            'view_image',
            'memories',
          ]) ...['-c', 'features.$feature=false'],
          'app-server',
          '--listen',
          'stdio://',
        ],
        workingDirectory: home.path,
        environment: environment,
        includeParentEnvironment: false,
      );
      _process = process;
      _subscriptions.add(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _onLine,
              onError: (_) => _disconnected(process),
              onDone: () => _disconnected(process),
            ),
      );
      // Drain diagnostics without logging prompts, account details or credentials.
      _subscriptions.add(process.stderr.listen((_) {}));
      await request('initialize', {
        'clientInfo': {
          'name': 'handdraw_studio',
          'title': 'HandDraw Studio',
          'version': AppBuildInfo.version,
        },
        'capabilities': {'experimentalApi': false},
      });
      _send({'method': 'initialized', 'params': <String, dynamic>{}});
    } catch (_) {
      await _stop();
      _connecting = null;
      rethrow;
    }
  }

  void _disconnected(Process process) {
    if (!identical(_process, process)) return;
    _process = null;
    _connecting = null;
    process.kill();
    _failPending('connectionLost');
  }

  void _onLine(String line) {
    try {
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic>) return;
      final id = value['id'];
      if (value.containsKey('method')) {
        if (id != null) {
          // This integration only accepts a declarative plan. It never grants
          // command, file, tool, permission, or account mutation requests.
          _send({
            'id': id,
            'error': {'code': -32601, 'message': 'Unsupported client request'},
          });
        } else if (!_events.isClosed) {
          _events.add(value);
        }
      } else if (id is int) {
        _requests.receive(value);
      }
    } on FormatException {
      /* Non-protocol diagnostics must not reach the UI. */
    }
  }

  void _send(Map<String, dynamic> value) {
    final process = _process;
    if (process == null) throw const CodexFailure('connectionLost');
    process.stdin.writeln(jsonEncode(value));
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    return _requests.request(method, params);
  }

  void _failPending(String reason) {
    _requests.disconnect(reason);
    if (!_events.isClosed) _events.add({'method': 'handdraw/disconnected'});
  }

  Future<void> _stop() async {
    final process = _process;
    _process = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _failPending('connectionLost');
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  @override
  Future<void> close() async {
    await _stop();
    _connecting = null;
  }
}

final class CodexFailure implements Exception {
  const CodexFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Correlates responses even after a start acknowledgement times out. A timed
/// out turn is never retried: its eventual id is used only to stop that turn.
class CodexRpcRequests {
  CodexRpcRequests({required this.send, required this.stop});
  final void Function(Map<String, dynamic>) send;
  final Future<void> Function() stop;
  final _pending = <int, _RpcRequest>{};
  int _nextId = 0;
  int _connectionEpoch = 0;

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = ++_nextId;
    final entry = _RpcRequest(params['threadId'] as String?);
    _pending[id] = entry;
    try {
      send({'id': id, 'method': method, 'params': params});
      return await entry.reply.future.timeout(
        timeout,
        onTimeout: () {
          entry.abandoned = method == 'turn/start';
          throw const CodexFailure('timeout');
        },
      );
    } finally {
      if (!entry.abandoned) _pending.remove(id);
    }
  }

  void receive(Map<String, dynamic> message) {
    final entry = _pending.remove(message['id']);
    if (entry == null) return;
    if (entry.abandoned) {
      if (!message.containsKey('error')) {
        unawaited(_stopLateTurn(entry, message['result']));
      }
      return;
    }
    if (message.containsKey('error')) {
      entry.reply.completeError(const CodexFailure('requestFailed'));
    } else {
      final result = message['result'];
      entry.reply.complete(
        result is Map ? Map<String, dynamic>.from(result) : {},
      );
    }
  }

  Future<void> _stopLateTurn(_RpcRequest entry, dynamic result) async {
    final epoch = _connectionEpoch;
    try {
      final turn = result is Map ? result['turn'] : null;
      final id = turn is Map ? turn['id'] : null;
      if (id is! String) throw const CodexFailure('requestFailed');
      await request('turn/interrupt', {
        'threadId': entry.threadId,
        'turnId': id,
      });
    } catch (_) {
      // A disconnected interruption must not shut down a newer connection.
      if (epoch == _connectionEpoch) await stop();
    }
  }

  void disconnect(String reason) {
    _connectionEpoch++;
    for (final entry in _pending.values) {
      if (!entry.abandoned && !entry.reply.isCompleted) {
        entry.reply.completeError(CodexFailure(reason));
      }
    }
    _pending.clear();
  }
}

class _RpcRequest {
  _RpcRequest(this.threadId);
  final String? threadId;
  final reply = Completer<Map<String, dynamic>>();
  bool abandoned = false;
}
