import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'support/edge_aware_golden_comparator.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = goldenFileComparator;
  if (!const bool.fromEnvironment('HANDDRAW_STRICT_GOLDENS') &&
      previous is LocalFileComparator) {
    goldenFileComparator = EdgeAwareGoldenComparator(
      previous.basedir.resolve('golden_test.dart'),
    );
  }
  // testMain registers tests; restoring here would remove the policy before
  // they execute. Each test file runs in its own isolate.
  await testMain();
}
