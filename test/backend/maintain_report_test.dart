// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('MaintainReport', () {
    RepoResult result(String name, RepoOutcome outcome, [String detail = '']) =>
        RepoResult(
          repo: OceanRepo.example(name: name),
          outcome: outcome,
          detail: detail,
        );

    test('example reports one published repo', () {
      expect(MaintainReport.example().lines(), [
        green('Published (1):'),
        '  ggsuite/gg_json: 1.2.4',
      ]);
    });

    test('groups by outcome and sorts by repo', () {
      final report = MaintainReport(
        results: [
          result('b', RepoOutcome.published, '2.0.0'),
          result('a', RepoOutcome.published, '1.0.1'),
          result('c', RepoOutcome.unchanged),
          result('d', RepoOutcome.changed, 'pubspec.yaml'),
          result('e', RepoOutcome.skipped, 'a test project'),
          result('f', RepoOutcome.blocked, 'waits for ggsuite/x'),
        ],
      );
      expect(report.lines(), [
        green('Published (2):'),
        '  ggsuite/a: 1.0.1',
        '  ggsuite/b: 2.0.0',
        blue('Would change (1):'),
        '  ggsuite/d: pubspec.yaml',
        darkGray('Unchanged (1):'),
        '  ggsuite/c',
        darkGray('Skipped (1):'),
        '  ggsuite/e: a test project',
        yellow('Blocked (1):'),
        '  ggsuite/f: waits for ggsuite/x',
      ]);
      expect(report.hasProblems, isTrue);
    });

    test('shows step, first line, clone and log of a failure', () {
      final report = MaintainReport(
        results: [
          RepoResult(
            repo: OceanRepo.example(),
            outcome: RepoOutcome.failed,
            detail: 'tests failed\nmore',
            step: 'commit',
            clonePath: 'run/ggsuite/gg_json',
            logPath: 'run/ggsuite/gg_json.log',
          ),
        ],
      );
      expect(report.lines(), [
        red('Failed (1):'),
        '  ggsuite/gg_json: commit: tests failed',
        '    clone: run/ggsuite/gg_json',
        '    log:   run/ggsuite/gg_json.log',
      ]);
    });

    test('has no problems when nothing failed', () {
      expect(MaintainReport.example().hasProblems, isFalse);
      expect(
        MaintainReport.example(results: [result('a', RepoOutcome.unchanged)])
            .lines(),
        [darkGray('Unchanged (1):'), '  ggsuite/a'],
      );
    });
  });
}
