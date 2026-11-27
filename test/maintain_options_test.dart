// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('MaintainTask', () {
    test('names its flag and subject', () {
      expect(MaintainTask.values.map((t) => t.flag), [
        'upgrade-sdk',
        'upgrade-deps',
        'upgrade-dna',
      ]);
      expect(MaintainTask.dna.subject, 'the DNA');
    });
  });

  group('MaintainOptions', () {
    group('example', () {
      test('upgrades everything', () {
        final options = MaintainOptions.example();
        expect(options.tasks, MaintainTask.values.toSet());
        expect(options.runId, '2026_10_28_074200');
        expect(options.major, isFalse);
        expect(options.jobs, 2);
        expect(options.dryRun, isFalse);
        expect(options.orgs, isEmpty);
        expect(options.repos, isEmpty);
        expect(options.script, isNull);
      });

      test('takes every value', () {
        final options = MaintainOptions.example(
          tasks: {MaintainTask.sdk},
          runId: 'r',
          major: true,
          jobs: 7,
          dryRun: true,
          orgs: ['ggsuite'],
          repos: ['gg_*'],
          script: '/x/migrate.dart',
        );
        expect(options.script, '/x/migrate.dart');
        expect(options.tasks, {MaintainTask.sdk});
        expect(options.runId, 'r');
        expect(options.major, isTrue);
        expect(options.jobs, 7);
        expect(options.dryRun, isTrue);
        expect(options.orgs, ['ggsuite']);
        expect(options.repos, ['gg_*']);
      });
    });

    test('survives a JSON round trip', () {
      final options = MaintainOptions.example(
        tasks: {MaintainTask.dna, MaintainTask.deps},
        runId: 'r',
        major: true,
        jobs: 3,
        orgs: ['ggsuite'],
        repos: ['gg_*'],
      );
      final json = options.toJson();
      expect(json['tasks'], ['upgrade-deps', 'upgrade-dna']);
      final read = MaintainOptions.fromJson(json);
      expect(read.toJson(), json);
      expect(read.dryRun, isFalse);
      expect(json.containsKey('script'), isFalse);
    });

    test('keeps the script in the JSON', () {
      final options = MaintainOptions.example(script: '/x/migrate.dart');
      final read = MaintainOptions.fromJson(options.toJson());
      expect(read.script, '/x/migrate.dart');
    });

    test('branch carries the run id', () {
      expect(MaintainOptions.example().branch, 'maintain_2026_10_28_074200');
    });

    group('message', () {
      String messageOf(Set<MaintainTask> tasks) =>
          MaintainOptions.example(tasks: tasks).message;

      test('names one task', () {
        expect(messageOf({MaintainTask.sdk}), 'Upgrade the SDK');
      });

      test('joins two tasks with and', () {
        expect(
          messageOf({MaintainTask.dna, MaintainTask.sdk}),
          'Upgrade the SDK and the DNA',
        );
      });

      test('names the script after the tasks', () {
        expect(
          MaintainOptions.example(
            tasks: {MaintainTask.dna},
            script: '/x/migrate.dart',
          ).message,
          'Upgrade the DNA and run migrate.dart',
        );
      });

      test('names the script alone', () {
        expect(
          MaintainOptions.example(tasks: {}, script: '/x/migrate.dart').message,
          'Run migrate.dart',
        );
      });

      test('lists three tasks in the fixed order', () {
        expect(
          messageOf(MaintainTask.values.toSet()),
          'Upgrade the SDK, the dependencies and the DNA',
        );
      });
    });

    test('runIdOf pads every part', () {
      expect(
        MaintainOptions.runIdOf(DateTime(2026, 1, 2, 3, 4, 5)),
        '2026_01_02_030405',
      );
    });
  });
}
