// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('DagScheduler', () {
    late List<String> started;
    late Map<String, List<String>> blocked;

    setUp(() {
      started = [];
      blocked = {};
    });

    Future<Map<String, bool>> run(
      Map<String, Set<String>> dependencies, {
      int jobs = 2,
      Set<String> failing = const {},
      Set<String> throwing = const {},
    }) => DagScheduler(jobs: jobs).run(
      dependencies: dependencies,
      task: (key) async {
        started.add(key);
        await Future<void>.delayed(Duration.zero);
        if (throwing.contains(key)) throw Exception(key);
        return !failing.contains(key);
      },
      onBlocked: (key, failed) => blocked[key] = failed,
    );

    test('example runs two at a time', () {
      expect(DagScheduler.example().jobs, 2);
      expect(DagScheduler.example(jobs: 5).jobs, 5);
    });

    test('completes at once without keys', () async {
      expect(await run({}), isEmpty);
    });

    test('starts a key only after its dependencies', () async {
      final results = await run({
        'app': {'lib'},
        'lib': {'base'},
        'base': {},
      });
      expect(started, ['base', 'lib', 'app']);
      expect(results, {'base': true, 'lib': true, 'app': true});
    });

    test('ignores dependencies outside the map', () async {
      final results = await run({
        'a': {'elsewhere'},
      });
      expect(results, {'a': true});
    });

    test('never runs more than jobs tasks at once', () async {
      var running = 0;
      var peak = 0;
      await const DagScheduler(jobs: 2).run(
        dependencies: {
          for (final key in ['a', 'b', 'c', 'd']) key: {},
        },
        task: (key) async {
          running++;
          peak = running > peak ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return true;
        },
        onBlocked: (_, _) {},
      );
      expect(peak, 2);
    });

    test('blocks the dependents of a failed key transitively', () async {
      final results = await run(
        {
          'base': {},
          'lib': {'base'},
          'app': {'lib'},
          'other': {},
        },
        failing: {'base'},
      );
      expect(started, ['base', 'other']);
      expect(results, {
        'base': false,
        'other': true,
        'lib': false,
        'app': false,
      });
      expect(blocked, {
        'lib': ['base'],
        'app': ['lib'],
      });
    });

    test('counts a throwing task as failed', () async {
      final results = await run(
        {
          'a': {},
          'b': {'a'},
        },
        throwing: {'a'},
      );
      expect(results, {'a': false, 'b': false});
      expect(blocked, {
        'b': ['a'],
      });
    });

    test('blocks the keys of a cycle', () async {
      final results = await run({
        'a': {'b'},
        'b': {'a'},
        'c': {},
      });
      expect(started, ['c']);
      expect(results, {'c': true, 'a': false, 'b': false});
      expect(blocked, {
        'a': ['b'],
        'b': ['a'],
      });
    });
  });
}
