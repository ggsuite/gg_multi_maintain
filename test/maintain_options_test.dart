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
        expect(options.versionIncrement, isNull);
        expect(options.pana, isTrue);
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
          versionIncrement: 'minor',
          pana: false,
        );
        expect(options.tasks, {MaintainTask.sdk});
        expect(options.runId, 'r');
        expect(options.major, isTrue);
        expect(options.jobs, 7);
        expect(options.dryRun, isTrue);
        expect(options.orgs, ['ggsuite']);
        expect(options.repos, ['gg_*']);
        expect(options.versionIncrement, 'minor');
        expect(options.pana, isFalse);
      });
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
