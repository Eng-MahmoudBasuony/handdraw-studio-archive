import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_image_context.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_account.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';

Map<String, dynamic> allowance({double used = 20, bool credits = false}) => {
  'rateLimitsByLimitId': <String, dynamic>{
    'codex': {
      'credits': {'hasCredits': credits, 'unlimited': false, 'balance': '0'},
      'primary': {'usedPercent': used},
      'secondary': {'usedPercent': 30},
    },
  },
};
const signedIn = <String, dynamic>{
  'account': {'type': 'chatgpt', 'planType': 'pro'},
};
Map<String, dynamic> planJson() => {
  'summary': 'Draw the panel, then the line.',
  'showHand': true,
  'confidence': .95,
  'parts': [
    {
      'name': 'Panel',
      'bounds': [.1, .1, .9, .9],
      'mode': 'reveal',
      'seconds': .5,
      'excludeText': true,
      'textId': '',
    },
    {
      'name': 'Command',
      'bounds': [0, 0, 1, 1],
      'mode': 'write',
      'seconds': 2,
      'excludeText': false,
      'textId': 'text-0',
    },
  ],
};
final texts = [
  SmartTextRegion(
    text: 'flutter pub get',
    confidence: .99,
    bounds: const Rect.fromLTWH(.2, .3, .5, .1),
  ),
];
final image = CodexImageContext(
  hash: 'image-v1',
  imageUrl: 'data:image/png;base64,fixture',
  texts: texts,
);

void main() {
  test(
    'subscription gate rejects API, credits, unknown limits and near exhaustion',
    () {
      expect(
        CodexAccount.fromResponses(signedIn, allowance()).blockedReason,
        isNull,
      );
      expect(
        CodexAccount.fromResponses({
          'account': {'type': 'apiKey'},
        }, allowance()).blockedReason,
        'chatgptRequired',
      );
      expect(
        CodexAccount.fromResponses(
          signedIn,
          allowance(credits: true),
        ).blockedReason,
        'creditsAvailable',
      );
      expect(
        CodexAccount.fromResponses(signedIn, allowance(used: 90)).blockedReason,
        'limitReached',
      );
      expect(
        CodexAccount.fromResponses(signedIn, {}).blockedReason,
        'limitsUnknown',
      );
      expect(
        CodexAccount.fromResponses(signedIn, {
          'rateLimits': {
            'primary': {'usedPercent': 1},
          },
        }).blockedReason,
        'limitsUnknown',
      );
      expect(
        CodexAccount(
          type: 'chatgpt',
          plan: 'pro',
          buckets: [{}],
          checkedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ).blockedReason,
        'limitsUnknown',
      );
      expect(
        CodexAccount.fromResponses({
          'account': {'type': 'chatgpt', 'planType': 'enterprise'},
        }, allowance()).blockedReason,
        'unsupportedPlan',
      );
    },
  );

  test(
    'unrelated Spark quota with null credits does not block image models',
    () {
      final limits = allowance();
      (limits['rateLimitsByLimitId'] as Map)['codex_bengalfox'] = {
        'limitId': 'codex_bengalfox',
        'credits': null,
        'primary': {'usedPercent': 100},
      };
      expect(
        CodexAccount.fromResponses(signedIn, limits).blockedReason,
        isNull,
      );
      final sparkOnly = {
        'rateLimits': {'limitId': 'codex_bengalfox', 'credits': null},
      };
      expect(
        CodexAccount.fromResponses(signedIn, sparkOnly).blockedReason,
        'limitsUnknown',
      );
    },
  );

  test('unscheduled OCR detections do not erase window controls', () {
    final plan = CodexDrawingPlan.parse(planJson(), [
      ...texts,
      const SmartTextRegion(
        text: 'OO',
        confidence: .8,
        bounds: Rect.fromLTRB(.7, .12, .8, .17),
      ),
    ]);
    expect(plan.regions.first.contains(const Offset(.75, .15)), isTrue);
    expect(plan.regions.first.contains(const Offset(.4, .35)), isFalse);
  });

  test('background excludes OCR and writing uses measured coordinates', () {
    final plan = CodexDrawingPlan.parse(planJson(), texts);
    final regions = plan.regions;
    expect(regions[0].contains(const Offset(.4, .35)), isFalse);
    expect(regions[0].contains(const Offset(.4, .7)), isTrue);
    expect(plan.parts[1].bounds, texts.single.bounds.inflate(.002));
    expect(plan.parts[0].seconds, .5);
  });

  test(
    'invalid geometry, unknown text and excessive duration cannot be applied',
    () {
      final bad = planJson();
      (bad['parts'] as List)[0]['bounds'] = [.8, .2, .1, .8];
      expect(() => CodexDrawingPlan.parse(bad, texts), throwsFormatException);
      final missing = planJson();
      (missing['parts'] as List)[1]['textId'] = 'text-99';
      expect(
        () => CodexDrawingPlan.parse(missing, texts),
        throwsFormatException,
      );
      final long = planJson();
      (long['parts'] as List)[0]['seconds'] = 10000;
      expect(() => CodexDrawingPlan.parse(long, texts), throwsFormatException);
    },
  );

  test(
    'login accepts only official HTTPS URLs without embedded credentials',
    () {
      expect(
        CodexAssistantCubit.isOfficialLoginUrl(
          'https://auth.openai.com/oauth/authorize',
        ),
        isTrue,
      );
      expect(
        CodexAssistantCubit.isOfficialLoginUrl(
          'https://auth.openai.com.evil.test/',
        ),
        isFalse,
      );
      expect(
        CodexAssistantCubit.isOfficialLoginUrl('http://auth.openai.com/'),
        isFalse,
      );
      expect(
        CodexAssistantCubit.isOfficialLoginUrl('https://user@auth.openai.com/'),
        isFalse,
      );
    },
  );

  test(
    'rechecks quota before inference and never sends a paid request',
    () async {
      final rpc = _FakeRpc();
      final cubit = CodexAssistantCubit(rpc);
      addTearDown(cubit.close);
      await cubit.connect();
      rpc.limits = allowance(credits: true);
      expect(await cubit.plan('Draw', image), isNull);
      expect(cubit.state.error, 'creditsAvailable');
      expect(rpc.methods, isNot(contains('turn/start')));
      expect(rpc.methods, isNot(contains('thread/start')));
    },
  );

  test(
    'one schema-constrained request reuses image context and caches identical requests',
    () async {
      final rpc = _FakeRpc();
      final cubit = CodexAssistantCubit(rpc);
      addTearDown(cubit.close);
      await cubit.connect();
      expect(await cubit.plan('Draw the panel then text', image), isNotNull);
      expect(cubit.state.plan!.parts, hasLength(2));
      expect(rpc.turnParams.single['outputSchema'], CodexDrawingPlan.schema);
      expect(
        (rpc.turnParams.single['input'] as List).where(
          (i) => i['type'] == 'image',
        ),
        hasLength(1),
      );
      await cubit.plan('Draw the panel then text', image);
      expect(rpc.turnParams, hasLength(1));
      await cubit.plan('Make text slower', image);
      expect(rpc.turnParams, hasLength(2));
      expect(
        (rpc.turnParams.last['input'] as List).where(
          (i) => i['type'] == 'image',
        ),
        isEmpty,
      );
      expect(rpc.methods.where((m) => m == 'thread/start'), hasLength(1));
      expect(rpc.turnParams.last['serviceTierForTurn'], 'default');
    },
  );

  test(
    'cancel while turn/start is pending interrupts that exact turn',
    () async {
      final rpc = _FakeRpc()..delayStart = Completer<Map<String, dynamic>>();
      final cubit = CodexAssistantCubit(rpc);
      addTearDown(cubit.close);
      await cubit.connect();
      final pending = cubit.plan('Draw', image);
      while (!rpc.methods.contains('turn/start')) {
        await Future<void>.delayed(Duration.zero);
      }
      await cubit.cancel();
      rpc.delayStart!.complete({
        'turn': {'id': 'delayed-turn'},
      });
      expect(await pending, isNull);
      expect(rpc.interrupts.single, {
        'threadId': 'thread-1',
        'turnId': 'delayed-turn',
      });
      expect(cubit.state.plan, isNull);
    },
  );
  test(
    'completion received before start acknowledgement is replayed',
    () async {
      final rpc = _FakeRpc()..delayStart = Completer<Map<String, dynamic>>();
      final cubit = CodexAssistantCubit(rpc);
      addTearDown(cubit.close);
      await cubit.connect();
      final pending = cubit.plan('Draw', image);
      while (rpc.turnParams.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      rpc.controller.add({
        'method': 'item/completed',
        'params': {
          'threadId': 'thread-1',
          'turnId': 'early-turn',
          'item': {'type': 'agentMessage', 'text': jsonEncode(planJson())},
        },
      });
      rpc.controller.add({
        'method': 'turn/completed',
        'params': {
          'threadId': 'thread-1',
          'turn': {'id': 'early-turn', 'status': 'completed'},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, CodexPhase.planning);
      rpc.delayStart!.complete({
        'turn': {'id': 'early-turn'},
      });
      expect(await pending, isNotNull);
    },
  );

  test('stale same-thread events cannot complete a pending new turn', () async {
    final rpc = _FakeRpc();
    final cubit = CodexAssistantCubit(rpc);
    addTearDown(cubit.close);
    await cubit.connect();
    expect(await cubit.plan('First', image), isNotNull);
    rpc.delayStart = Completer<Map<String, dynamic>>();
    final pending = cubit.plan('Second', image);
    while (rpc.turnParams.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    void finish(String id, String text) {
      rpc.controller.add({
        'method': 'item/completed',
        'params': {
          'threadId': 'thread-1',
          'turnId': id,
          'item': {'type': 'agentMessage', 'text': text},
        },
      });
      rpc.controller.add({
        'method': 'turn/completed',
        'params': {
          'threadId': 'thread-1',
          'turn': {'id': id, 'status': 'completed'},
        },
      });
    }

    finish('turn-1', 'stale invalid JSON');
    await Future<void>.delayed(Duration.zero);
    rpc.delayStart!.complete({
      'turn': {'id': 'turn-2'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.phase, CodexPhase.planning);
    finish('turn-1', 'another stale message');
    finish('turn-2', jsonEncode(planJson()));
    expect(await pending, isNotNull);
    expect(cubit.state.error, isNull);
  });

  test(
    'scene requests use the account gate and contain no image input',
    () async {
      final rpc = _FakeRpc();
      final cubit = CodexAssistantCubit(rpc);
      addTearDown(cubit.close);
      await cubit.connect();
      final result = await cubit.design('Cloud backup scene', {
        'type': 'object',
      });
      expect(result, isNotNull);
      expect(rpc.turnParams, hasLength(1));
      expect((rpc.turnParams.single['input'] as List).single['type'], 'text');
      rpc.limits = allowance(credits: true);
      expect(await cubit.design('Another scene', {'type': 'object'}), isNull);
      expect(rpc.turnParams, hasLength(1));
    },
  );
}

class _FakeRpc implements CodexRpc {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final methods = <String>[];
  final turnParams = <Map<String, dynamic>>[];
  final interrupts = <Map<String, dynamic>>[];
  Map<String, dynamic> limits = allowance();
  Completer<Map<String, dynamic>>? delayStart;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {
    await controller.close();
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    methods.add(method);
    switch (method) {
      case 'account/read':
        return signedIn;
      case 'account/rateLimits/read':
        return limits;
      case 'model/list':
        return {
          'data': [
            {
              'model': 'fixture-model',
              'displayName': 'Fixture',
              'isDefault': true,
              'inputModalities': ['text', 'image'],
              'supportedReasoningEfforts': [
                {'reasoningEffort': 'low'},
              ],
            },
          ],
        };
      case 'thread/start':
        return {
          'thread': {'id': 'thread-1'},
        };
      case 'turn/start':
        turnParams.add(params);
        if (delayStart != null) return delayStart!.future;
        scheduleMicrotask(() {
          controller.add({
            'method': 'item/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {'type': 'agentMessage', 'text': jsonEncode(planJson())},
            },
          });
          controller.add({
            'method': 'turn/completed',
            'params': {
              'threadId': 'thread-1',
              'turn': {'id': 'turn-1', 'status': 'completed'},
            },
          });
        });
        return {
          'turn': {'id': 'turn-1'},
        };
      case 'turn/interrupt':
        interrupts.add(params);
        return {};
      default:
        return {};
    }
  }
}
