/// Subscription-only gate. Unknown limits and credit-funded accounts fail closed.
final class CodexAccount {
  const CodexAccount({
    required this.type,
    required this.plan,
    this.email,
    this.buckets = const [],
    this.checkedAt,
  });
  final String type;
  final String plan;
  final String? email;
  final List<Map<String, dynamic>> buckets;
  final DateTime? checkedAt;
  bool get isChatGpt => type == 'chatgpt';

  String? get blockedReason {
    if (!isChatGpt) return 'chatgptRequired';
    if (!{'plus', 'pro', 'prolite'}.contains(plan)) return 'unsupportedPlan';
    if (checkedAt == null ||
        DateTime.now().difference(checkedAt!) > const Duration(seconds: 30)) {
      return 'limitsUnknown';
    }
    if (buckets.isEmpty) return 'limitsUnknown';
    for (final bucket in buckets) {
      final credits = bucket['credits'];
      if (credits is! Map ||
          credits['hasCredits'] is! bool ||
          credits['unlimited'] is! bool) {
        return 'limitsUnknown';
      }
      // The protocol has no per-turn "never use credits" switch. Do not start
      // a request that could fall back to an existing monetary credit balance.
      if (credits['hasCredits'] == true || credits['unlimited'] == true) {
        return 'creditsAvailable';
      }
      if (bucket['rateLimitReachedType'] != null) return 'limitReached';
      var windows = 0;
      for (final key in ['primary', 'secondary']) {
        final window = bucket[key];
        if (window == null) continue;
        if (window is! Map) return 'limitsUnknown';
        final used = window['usedPercent'];
        if (used is! num || !used.isFinite || used < 0 || used > 100) {
          return 'limitsUnknown';
        }
        windows++;
        // Reserve capacity rather than starting near an exhausted allowance.
        if (used >= 90) return 'limitReached';
      }
      if (windows == 0) return 'limitsUnknown';
    }
    return null;
  }

  factory CodexAccount.fromResponses(
    Map<String, dynamic> accountResponse,
    Map<String, dynamic>? limits,
  ) {
    final account = accountResponse['account'];
    final raw = account is Map ? account : const {};
    final byId = limits?['rateLimitsByLimitId'];
    final buckets = <Map<String, dynamic>>[];
    // Image-capable Codex models use the main Codex allowance. Spark has a
    // separate text-only bucket whose credits can legitimately be null.
    final main = byId is Map ? byId['codex'] : null;
    final selected = main is Map ? main : limits?['rateLimits'];
    if (selected is Map) {
      final id = selected['limitId'];
      if (id == null || id == 'codex') {
        buckets.add(Map<String, dynamic>.from(selected));
      }
    }

    return CodexAccount(
      type: raw['type'] as String? ?? 'signedOut',
      plan: raw['planType'] as String? ?? 'unknown',
      email: raw['email'] as String?,
      buckets: List.unmodifiable(buckets),
      checkedAt: limits == null ? null : DateTime.now(),
    );
  }
}
