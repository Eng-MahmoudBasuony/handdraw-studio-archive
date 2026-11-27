# Project container benchmark

Isolated Step 3A research harness. Its dependencies are intentionally not
connected to the production Flutter application.

Run tests:

```sh
dart test
```

The normal command includes the 70,000-entry ZIP64 gate. For a fast portable
contract run (the command used by the Windows/macOS CI matrix):

```sh
dart test --exclude-tags large
```

Qualification evidence and limits are recorded in
`docs/architecture/adr_project_container_zip_dependency_qualification.md`.

Run a benchmark in a system temporary directory:

```sh
dart run bin/container_benchmark.dart --sizes=50,500,2048
```

For decision-grade measurements, compile the coordinator and its workers to
AOT first so JIT warm-up is not mixed into save/open/read timings:

```sh
dart compile exe bin/container_benchmark.dart -o build/container_benchmark_aot
./build/container_benchmark_aot --sizes=50,500,2048
```

The harness checks free disk space before large fixtures, deletes generated
fixtures and archives in `finally`, and writes only the requested JSON report.
The root Flutter app has no dependency on any evaluated archive package.
