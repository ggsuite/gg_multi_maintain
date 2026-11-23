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

    test('example reports one merged repo', () {
      expect(MaintainReport.example().lines(), [
        green('Merged (1):'),
        '  ggsuite/gg_json: pubspec.yaml',
      ]);
    });

    test('groups by outcome and sorts by repo', () {
      final report = MaintainReport(
        results: [
          result('b', RepoOutcome.merged, '2.0.0'),
          result('a', RepoOutcome.merged, '1.0.1'),
          result('c', RepoOutcome.unchanged),
          result('d', RepoOutcome.changed, 'pubspec.yaml'),
          result('e', RepoOutcome.skipped, 'a test project'),
          result('f', RepoOutcome.blocked, 'waits for ggsuite/x'),
        ],
      );
      expect(report.lines(), [
        green('Merged (2):'),
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

    test('shows step, first line, checkout and log of a failure', () {
      final report = MaintainReport(
        results: [
          RepoResult(
            repo: OceanRepo.example(),
            outcome: RepoOutcome.failed,
            detail: 'tests failed\nmore',
            step: 'commit',
            checkoutPath: 'run/ggsuite/gg_json',
            logPath: 'run/ggsuite/gg_json.log',
          ),
        ],
      );
      expect(report.lines(), [
        red('Failed (1):'),
        '  ggsuite/gg_json: commit: tests failed',
        '    checkout: run/ggsuite/gg_json',
        '    log:   run/ggsuite/gg_json.log',
      ]);
    });

    test('lines without colors and the text of the report file', () {
      final report = MaintainReport(
        results: [
          result('a', RepoOutcome.merged, '1.0.1'),
          RepoResult(
            repo: OceanRepo.example(name: 'b'),
            outcome: RepoOutcome.failed,
            detail: 'tests failed',
            step: 'commit',
          ),
        ],
      );
      expect(report.lines(colored: false), [
        'Merged (1):',
        '  ggsuite/a: 1.0.1',
        'Failed (1):',
        '  ggsuite/b: commit: tests failed',
      ]);
      expect(
        report.text(runId: '2026_11_15_020000'),
        [
          'gg do maintain, run 2026_11_15_020000',
          '',
          'Merged (1):',
          '  ggsuite/a: 1.0.1',
          'Failed (1):',
          '  ggsuite/b: commit: tests failed',
          '',
        ].join('\n'),
      );
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
