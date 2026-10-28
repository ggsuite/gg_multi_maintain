// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

// #############################################################################
/// Runs a task per key in parallel, but a key only after its dependencies.
///
/// A key starts as soon as every dependency succeeded and a slot is free.
/// A key whose dependency failed or was blocked never starts; it is reported
/// to `onBlocked` instead. That way a repo is only maintained once the repos
/// it depends on are published.
class DagScheduler {
  /// Constructor
  const DagScheduler({required this.jobs})
    : assert(jobs > 0, 'jobs must be at least 1');

  /// A scheduler running two tasks at a time.
  factory DagScheduler.example({int? jobs}) => DagScheduler(jobs: jobs ?? 2);

  // ...........................................................................
  /// How many tasks run at the same time.
  final int jobs;

  // ...........................................................................
  /// Runs [task] for every key of [dependencies] and returns which succeeded.
  ///
  /// - [dependencies] maps each key to the keys it waits for; keys outside
  ///   the map are ignored. The map's order decides who starts first.
  /// - [task] returns true when its dependents may start. A throw counts as
  ///   false.
  /// - [onBlocked] gets a key that cannot start and the dependencies that
  ///   did not succeed.
  Future<Map<String, bool>> run({
    required Map<String, Set<String>> dependencies,
    required Future<bool> Function(String key) task,
    required void Function(String key, List<String> failed) onBlocked,
  }) {
    final run = _Run(
      jobs: jobs,
      dependencies: dependencies,
      task: task,
      onBlocked: onBlocked,
    );
    return run.start();
  }
}

// #############################################################################
class _Run {
  _Run({
    required this.jobs,
    required Map<String, Set<String>> dependencies,
    required this.task,
    required this.onBlocked,
  }) : dependencies = {
         for (final entry in dependencies.entries)
           entry.key: entry.value.where(dependencies.containsKey).toSet(),
       },
       pending = dependencies.keys.toList();

  final int jobs;
  final Map<String, Set<String>> dependencies;
  final Future<bool> Function(String key) task;
  final void Function(String key, List<String> failed) onBlocked;

  final List<String> pending;
  final Map<String, bool> results = {};
  final Completer<Map<String, bool>> done = Completer();
  int running = 0;

  // ...........................................................................
  Future<Map<String, bool>> start() {
    _next();
    return done.future;
  }

  // ...........................................................................
  void _next() {
    _blockUnreachable();
    for (final key in [...pending]) {
      if (running >= jobs) break;
      if (!dependencies[key]!.every(results.containsKey)) continue;
      pending.remove(key);
      _start(key);
    }
    if (running > 0) return;
    _blockCycles();
    done.complete(results);
  }

  // ...........................................................................
  /// Blocks what still waits when nothing runs: the keys of a cycle.
  void _blockCycles() {
    final waiting = {...pending};
    pending.clear();
    for (final key in waiting) {
      results[key] = false;
      onBlocked(key, dependencies[key]!.where(waiting.contains).toList());
    }
  }

  // ...........................................................................
  void _blockUnreachable() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final key in [...pending]) {
        final failed = dependencies[key]!
            .where((dependency) => results[dependency] == false)
            .toList();
        if (failed.isEmpty) continue;
        pending.remove(key);
        results[key] = false;
        onBlocked(key, failed);
        changed = true;
      }
    }
  }

  // ...........................................................................
  void _start(String key) {
    running++;
    unawaited(
      Future(() => task(key))
          .then((success) => success, onError: (Object _) => false)
          .then((success) {
            results[key] = success;
            running--;
            _next();
          }),
    );
  }
}
