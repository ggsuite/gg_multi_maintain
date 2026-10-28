// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('RepoOutcome', () {
    test('lets dependents run unless failed or blocked', () {
      expect(RepoOutcome.values.where((o) => o.letsDependentsRun), [
        RepoOutcome.published,
        RepoOutcome.changed,
        RepoOutcome.unchanged,
        RepoOutcome.skipped,
      ]);
      expect(RepoOutcome.failed.title, 'Failed');
    });
  });

  group('RepoResult', () {
    test('example is a published repo', () {
      final result = RepoResult.example();
      expect(result.repo.key, 'ggsuite/gg_json');
      expect(result.outcome, RepoOutcome.published);
      expect(result.detail, '1.2.4');
      expect(result.step, isNull);
      expect(result.clonePath, isNull);
      expect(result.logPath, isNull);
    });

    test('example takes every value', () {
      final result = RepoResult.example(
        repo: OceanRepo.example(name: 'x'),
        outcome: RepoOutcome.failed,
        detail: 'boom',
        step: 'commit',
        clonePath: 'c',
        logPath: 'l',
      );
      expect(result.repo.name, 'x');
      expect(result.outcome, RepoOutcome.failed);
      expect(
        [result.detail, result.step, result.clonePath, result.logPath],
        ['boom', 'commit', 'c', 'l'],
      );
    });

    test('defaults to an empty detail', () {
      final result = RepoResult(
        repo: OceanRepo.example(),
        outcome: RepoOutcome.unchanged,
      );
      expect(result.detail, '');
    });
  });
}
