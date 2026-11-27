import 'dart:io';

Future<void> main(List<String> arguments) async {
  final output =
      _value(arguments, '--output') ?? 'build/path_benchmark_report.json';
  final flutter = Platform.environment['FLUTTER'] ?? 'flutter';
  final testArguments = <String>[
    'test',
    'test/path_benchmark_test.dart',
    if (arguments.contains('--extended'))
      '--dart-define=HANDDRAW_BENCHMARK_EXTENDED=true',
    if (arguments.contains('--sparse-thinning'))
      '--dart-define=HANDDRAW_SPIKE_SPARSE_THINNING=true',
    '--dart-define=HANDDRAW_BENCHMARK_OUTPUT=$output',
  ];
  stdout.writeln('Running deterministic HandDraw path benchmark…');
  final process = await Process.start(
    flutter,
    testArguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Path benchmark failed quality thresholds.');
    exit(exitCode);
  }
  stdout.writeln('Benchmark report: $output');
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}
