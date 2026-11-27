import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';

void main() {
  test('late successful start is interrupted after caller timeout', () async {
    final sent = <Map<String, dynamic>>[];
    var stopped = false;
    final requests = CodexRpcRequests(
      send: sent.add,
      stop: () async {
        stopped = true;
      },
    );
    await expectLater(
      requests.request('turn/start', {
        'threadId': 'original-thread',
      }, timeout: Duration.zero),
      throwsA(isA<CodexFailure>().having((e) => e.code, 'code', 'timeout')),
    );
    requests.receive({
      'id': sent.first['id'],
      'result': {
        'turn': {'id': 'late-turn'},
      },
    });
    expect(sent.last['method'], 'turn/interrupt');
    expect(sent.last['params'], {
      'threadId': 'original-thread',
      'turnId': 'late-turn',
    });
    requests.receive({'id': sent.last['id'], 'result': {}});
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(sent.where((r) => r['method'] == 'turn/start'), hasLength(1));
  });

  test('failed late interruption closes transport', () async {
    final sent = <Map<String, dynamic>>[];
    final stopped = Completer<void>();
    final requests = CodexRpcRequests(
      send: sent.add,
      stop: () async {
        stopped.complete();
      },
    );
    await expectLater(
      requests.request('turn/start', {
        'threadId': 'thread',
      }, timeout: Duration.zero),
      throwsA(isA<CodexFailure>()),
    );
    requests.receive({
      'id': sent.first['id'],
      'result': {
        'turn': {'id': 'late'},
      },
    });
    requests.receive({
      'id': sent.last['id'],
      'error': {'code': -1},
    });
    await stopped.future;
  });

  test('failed old interruption cannot stop a reconnected transport', () async {
    final sent = <Map<String, dynamic>>[];
    var stopCalls = 0;
    final requests = CodexRpcRequests(
      send: sent.add,
      stop: () async {
        stopCalls++;
      },
    );
    await expectLater(
      requests.request('turn/start', {
        'threadId': 'old-thread',
      }, timeout: Duration.zero),
      throwsA(isA<CodexFailure>()),
    );
    requests.receive({
      'id': sent.first['id'],
      'result': {
        'turn': {'id': 'old-turn'},
      },
    });
    expect(sent.last['method'], 'turn/interrupt');
    requests.disconnect('connectionLost');
    final newRequest = requests.request('account/read', {});
    await Future<void>.delayed(Duration.zero);
    expect(stopCalls, 0);
    requests.receive({
      'id': sent.last['id'],
      'result': {'connected': true},
    });
    expect(await newRequest, {'connected': true});
  });

  test('late rejected start does not interrupt or retry', () async {
    final sent = <Map<String, dynamic>>[];
    final requests = CodexRpcRequests(send: sent.add, stop: () async {});
    await expectLater(
      requests.request('turn/start', {
        'threadId': 'thread',
      }, timeout: Duration.zero),
      throwsA(isA<CodexFailure>()),
    );
    requests.receive({
      'id': sent.first['id'],
      'error': {'code': -1},
    });
    expect(sent, hasLength(1));
  });

  test(
    'disconnect drops abandoned correlation and fails active requests',
    () async {
      final sent = <Map<String, dynamic>>[];
      final requests = CodexRpcRequests(send: sent.add, stop: () async {});
      await expectLater(
        requests.request('turn/start', {
          'threadId': 'thread',
        }, timeout: Duration.zero),
        throwsA(isA<CodexFailure>()),
      );
      final pending = requests.request('account/read', {});
      final expectation = expectLater(
        pending,
        throwsA(
          isA<CodexFailure>().having((e) => e.code, 'code', 'connectionLost'),
        ),
      );
      requests.disconnect('connectionLost');
      await expectation;
      requests.receive({
        'id': sent.first['id'],
        'result': {
          'turn': {'id': 'late'},
        },
      });
      expect(sent, hasLength(2));
    },
  );
}
