// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../helpers/git_fixture.dart';

// #############################################################################
/// Ends each repo as [outcomes] says, without touching git.
class _ScriptedMaintainer extends RepoMaintainer {
  _ScriptedMaintainer({
    required super.options,
    required super.runDir,
    required this.outcomes,
    required this.started,
  });

  final Map<String, RepoOutcome> outcomes;
  final List<String> started;

  @override
  Future<RepoResult> maintain({
    required OceanRepo repo,
    required void Function(String) ggLog,
    String? logPath,
  }) async {
    started.add(repo.key);
    ggLog('working on ${repo.name}');
    final outcome = outcomes[repo.key] ?? RepoOutcome.unchanged;
    if (outcome == RepoOutcome.failed) {
      GitFixture.writeFiles(cloneDirOf(repo), {'pubspec.yaml': 'name: x'});
    }
    return RepoResult(
      repo: repo,
      outcome: outcome,
      detail: outcome == RepoOutcome.failed ? 'tests failed' : '',
      step: outcome == RepoOutcome.failed ? 'commit' : null,
      clonePath: outcome == RepoOutcome.failed ? cloneDirOf(repo).path : null,
      logPath: logPath,
    );
  }
}

void main() {
  group('Maintainer', () {
    late GitFixture fixture;
    late List<String> log;
    late List<String> started;
    late Map<String, RepoOutcome> outcomes;

    setUp(() {
      fixture = GitFixture();
      log = [];
      started = [];
      outcomes = {};
      fixture.oceanRepo('ggsuite', 'base', url: 'https://x/ggsuite/base.git');
      fixture.oceanRepo(
        'ggsuite',
        'app',
        files: {
          'pubspec.yaml': GitFixture.pubspec(
            'app',
            dependencies: {'base': '^1.0.0'},
          ),
        },
        url: 'https://x/ggsuite/app.git',
      );
      fixture.oceanRepo(
        'ggsuite',
        'testproject_gg_1',
        url: 'https://x/ggsuite/testproject_gg_1.git',
      );
    });

    Directory maintainDir() => Directory(
      path.join(fixture.root.path, 'workspace', Maintainer.maintainFolder),
    );

    Future<MaintainReport> run({MaintainOptions? options}) =>
        Maintainer(
          selection: RepoSelection(
            publishTargets: (_) async => {PublishTarget.pubDev},
          ),
          repoMaintainer: (options, runDir) => _ScriptedMaintainer(
            options: options,
            runDir: runDir,
            outcomes: outcomes,
            started: started,
          ),
        ).run(
          oceanPath: fixture.ocean.path,
          options: options ?? MaintainOptions.example(),
          ggLog: log.add,
        );

    test('runs the dependencies first and reports all repos', () async {
      outcomes['ggsuite/base'] = RepoOutcome.published;
      final report = await run();
      expect(started, ['ggsuite/base', 'ggsuite/app']);
      expect(report.hasProblems, isFalse);
      expect(
        {for (final r in report.results) r.repo.key: r.outcome},
        {
          'ggsuite/testproject_gg_1': RepoOutcome.skipped,
          'ggsuite/base': RepoOutcome.published,
          'ggsuite/app': RepoOutcome.unchanged,
        },
      );
      expect(
        log.first,
        contains(
          'Running --upgrade-sdk --upgrade-deps '
          '--upgrade-dna in 2 repos, 2 at a time.',
        ),
      );
      expect(log, contains(contains('working on base')));
      expect(log, contains(contains('Published (1):')));
      expect(maintainDir().existsSync(), isFalse);
    });

    test('blocks the dependents of a failed repo, keeps its log', () async {
      outcomes['ggsuite/base'] = RepoOutcome.failed;
      final report = await run();
      expect(started, ['ggsuite/base']);
      expect(report.hasProblems, isTrue);
      final app = report.results.firstWhere((r) => r.repo.name == 'app');
      expect(app.outcome, RepoOutcome.blocked);
      expect(app.detail, 'waits for ggsuite/base');

      final runDir = Directory(
        path.join(maintainDir().path, '2026_10_28_074200', 'ggsuite'),
      );
      expect(Directory(path.join(runDir.path, 'base')).existsSync(), isTrue);
      final baseLog = File(path.join(runDir.path, 'base.log'));
      expect(baseLog.readAsStringSync(), 'working on base\n');
      expect(File(path.join(runDir.path, 'app.log')).existsSync(), isFalse);
    });

    test('says when it only tries', () async {
      await run(options: MaintainOptions.example(dryRun: true));
      expect(log.first, contains('Trying'));
    });

    test('reports only the skipped repos when nothing is left', () async {
      final report = await run(
        options: MaintainOptions.example(repos: ['testproject_*']),
      );
      expect(started, isEmpty);
      expect(report.results.single.outcome, RepoOutcome.skipped);
    });

    test('maintains with the real steps by default', () async {
      fixture.oceanRepo(
        'ggsuite',
        'gone',
        url: path.join(fixture.root.path, 'no_such_remote'),
      );
      final report =
          await Maintainer(
            selection: RepoSelection(
              publishTargets: (_) async => {PublishTarget.pubDev},
            ),
          ).run(
            oceanPath: fixture.ocean.path,
            options: MaintainOptions.example(repos: ['gone']),
            ggLog: log.add,
          );
      final result = report.results.single;
      expect(result.outcome, RepoOutcome.failed);
      expect(result.step, 'clone');
    });

    test('example uses the real steps', () {
      expect(Maintainer.example, returnsNormally);
    });
  });
}
