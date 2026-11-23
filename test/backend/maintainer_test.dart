// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../helpers/git_fixture.dart';

// #############################################################################
/// Ends each repo as [outcomes] says, without touching git.
class _ScriptedMaintainer extends RepoMaintainer {
  _ScriptedMaintainer({
    required super.options,
    required this.outcomes,
    required this.started,
  });

  final Map<String, RepoOutcome> outcomes;
  final List<String> started;

  @override
  Future<RepoResult> maintain({
    required OceanRepo repo,
    required Directory dir,
    required String base,
    required void Function(String) ggLog,
    String? logPath,
    bool resume = false,
  }) async {
    started.add('${repo.key}${resume ? ' (resumed)' : ''}');
    ggLog('working on ${repo.name} from ${base.substring(0, 7)}');
    final outcome = outcomes[repo.key] ?? RepoOutcome.unchanged;
    final failed = outcome == RepoOutcome.failed;
    return RepoResult(
      repo: repo,
      outcome: outcome,
      detail: failed ? 'tests failed' : '',
      step: failed ? 'commit' : null,
      checkoutPath: failed ? dir.path : null,
      logPath: logPath,
    );
  }
}

// #############################################################################
/// Creates no ticket but records what it was asked to do.
class _RecordingHost extends CloneRepoHost {
  _RecordingHost({
    required super.root,
    required this.calls,
    required this.notAdded,
  });

  final List<String> calls;

  /// Repos [add] leaves out before it throws.
  final Set<String> notAdded;

  @override
  Future<void> add({
    required Directory folder,
    required String oceanPath,
    required MaintainOptions options,
    required List<OceanRepo> repos,
    required void Function(String) ggLog,
  }) async {
    calls.add('add ${repos.map((r) => r.name).join(', ')}');
    await super.add(
      folder: folder,
      oceanPath: oceanPath,
      options: options,
      repos: repos.where((r) => !notAdded.contains(r.key)).toList(),
      ggLog: ggLog,
    );
    if (repos.any((r) => notAdded.contains(r.key))) {
      throw Exception('fetch failed');
    }
  }

  @override
  Future<void> prepare({
    required String workspacePath,
    required void Function(String) ggLog,
  }) async => calls.add('prepare');

  @override
  Future<void> close({
    required Directory folder,
    required void Function(String) ggLog,
  }) async {
    calls.add('close');
    await super.close(folder: folder, ggLog: ggLog);
  }
}

void main() {
  group('Maintainer', () {
    late GitFixture fixture;
    late List<String> log;
    late List<String> started;
    late List<String> calls;
    late Map<String, RepoOutcome> outcomes;
    late Directory runs;
    late Set<String> notAdded;

    setUp(() {
      fixture = GitFixture();
      log = [];
      started = [];
      calls = [];
      outcomes = {};
      notAdded = {};
      runs = Directory(path.join(fixture.root.path, 'runs'));
      fixture.oceanRepo(
        'ggsuite',
        'base',
        url: fixture.remote('base', GitFixture.dartPackage('base')),
      );
      final app = {
        ...GitFixture.dartPackage('app'),
        'pubspec.yaml': GitFixture.pubspec(
          'app',
          dependencies: {'base': '^1.0.0'},
        ),
      };
      fixture.oceanRepo(
        'ggsuite',
        'app',
        files: app,
        url: fixture.remote('app', app),
      );
      fixture.oceanRepo('ggsuite', 'local_only');
    });

    Directory runFolder() =>
        Directory(path.join(runs.path, 'gg_maintain_2026_10_28_074200'));

    Maintainer maintainer() => Maintainer(
      repoMaintainer: (options) => _ScriptedMaintainer(
        options: options,
        outcomes: outcomes,
        started: started,
      ),
      host: ({required dryRun}) {
        calls.add('host${dryRun ? ' (dry run)' : ''}');
        return _RecordingHost(root: runs, calls: calls, notAdded: notAdded);
      },
    );

    Future<MaintainReport> run({MaintainOptions? options}) => maintainer().run(
      oceanPath: fixture.ocean.path,
      options: options ?? MaintainOptions.example(),
      ggLog: log.add,
    );

    Future<MaintainReport> resume() => maintainer().resume(
      folder: runFolder(),
      oceanPath: fixture.ocean.path,
      ggLog: log.add,
    );

    test('runs the dependencies first and removes the folder', () async {
      outcomes['ggsuite/base'] = RepoOutcome.merged;
      final report = await run();
      expect(started, ['ggsuite/base', 'ggsuite/app']);
      expect(calls, ['host', 'prepare', 'add app, base', 'close']);
      expect(report.hasProblems, isFalse);
      expect(
        {for (final r in report.results) r.repo.key: r.outcome},
        {
          'ggsuite/local_only': RepoOutcome.skipped,
          'ggsuite/base': RepoOutcome.merged,
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
      expect(log, contains(contains('working on base from ')));
      expect(log, contains(contains('Merged (1):')));
      expect(runFolder().existsSync(), isFalse);
    });

    test('keeps the folder with state, report and log on problems', () async {
      outcomes['ggsuite/base'] = RepoOutcome.failed;
      final report = await run();
      expect(started, ['ggsuite/base']);
      expect(calls, ['host', 'prepare', 'add app, base']);
      expect(report.hasProblems, isTrue);
      final app = report.results.firstWhere((r) => r.repo.name == 'app');
      expect(app.outcome, RepoOutcome.blocked);
      expect(app.detail, 'waits for ggsuite/base');

      final folder = runFolder();
      final logs = path.join(folder.path, Maintainer.logFolder, 'ggsuite');
      expect(
        File(path.join(logs, 'base.log')).readAsStringSync(),
        startsWith('working on base from '),
      );
      expect(File(path.join(logs, 'app.log')).existsSync(), isFalse);

      final text = File(path.join(folder.path, Maintainer.reportFile))
          .readAsStringSync();
      expect(text, startsWith('gg do maintain, run 2026_10_28_074200'));
      expect(text, contains('  ggsuite/base: commit: tests failed'));
      expect(text, contains('  ggsuite/app: waits for ggsuite/base'));
      expect(text, isNot(contains('\x1B')));
      expect(log, contains(contains('--continue -i gg_maintain_')));

      final state = MaintainState.load(folder)!;
      expect(state.results['ggsuite/base']!.outcome, RepoOutcome.failed);
      expect(state.results['ggsuite/app']!.outcome, RepoOutcome.blocked);
      expect(state.bases.keys, ['ggsuite/base']);
    });

    test('continues with the repos that are not done', () async {
      outcomes['ggsuite/base'] = RepoOutcome.failed;
      await run(options: MaintainOptions.example(jobs: 1));
      started.clear();
      calls.clear();
      log.clear();

      outcomes['ggsuite/base'] = RepoOutcome.merged;
      final report = await resume();
      expect(report.hasProblems, isFalse);
      expect(started, ['ggsuite/base (resumed)', 'ggsuite/app (resumed)']);
      expect(calls, ['host', 'close']);
      expect(log.first, contains('Continuing'));
      expect(log.first, contains('in 2 repos, 1 at a time.'));
      expect(runFolder().existsSync(), isFalse);
    });

    test('does not repeat what is done when continuing', () async {
      outcomes['ggsuite/app'] = RepoOutcome.failed;
      await run();
      started.clear();
      outcomes.clear();
      await resume();
      expect(started, ['ggsuite/app (resumed)']);
    });

    test('adds missing checkouts again when continuing', () async {
      outcomes['ggsuite/base'] = RepoOutcome.failed;
      await run();
      Directory(path.join(runFolder().path, 'ggsuite', 'app'))
          .deleteSync(recursive: true);
      calls.clear();
      started.clear();
      outcomes.clear();
      final report = await resume();
      expect(calls, ['host', 'add app', 'close']);
      expect(started, ['ggsuite/base (resumed)', 'ggsuite/app (resumed)']);
      expect(report.hasProblems, isFalse);
    });

    test('blocks the dependents of a repo it could not add', () async {
      notAdded.add('ggsuite/base');
      final report = await run();
      expect(log, contains(contains('Could not add all repos')));
      expect(started, isEmpty);
      final results = {for (final r in report.results) r.repo.key: r};
      expect(results['ggsuite/base']!.outcome, RepoOutcome.failed);
      expect(results['ggsuite/base']!.step, 'find the checkout');
      expect(results['ggsuite/app']!.outcome, RepoOutcome.blocked);
      expect(MaintainState.load(runFolder()), isNotNull);

      // The next try adds it.
      notAdded.clear();
      expect((await resume()).hasProblems, isFalse);
      expect(started, ['ggsuite/base (resumed)', 'ggsuite/app (resumed)']);
    });

    test('fails a repo whose checkout git cannot read', () async {
      outcomes['ggsuite/app'] = RepoOutcome.failed;
      await run();
      final state = MaintainState.load(runFolder())!;
      state.bases.remove('ggsuite/app');
      state.save(runFolder());
      final head = File(
        path.join(runFolder().path, 'ggsuite', 'app', '.git', 'HEAD'),
      )..writeAsStringSync('broken');
      expect(head.existsSync(), isTrue);
      final report = await resume();
      final app = report.results.firstWhere((r) => r.repo.name == 'app');
      expect(app.outcome, RepoOutcome.failed);
      expect(app.step, 'find the checkout');
    });

    test('refuses to continue a folder without a run', () async {
      await expectLater(
        maintainer().resume(
          folder: fixture.root,
          oceanPath: fixture.ocean.path,
          ggLog: log.add,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('holds no run of gg do maintain'),
          ),
        ),
      );
    });

    test('says when it only tries and keeps no state', () async {
      outcomes['ggsuite/base'] = RepoOutcome.failed;
      await run(options: MaintainOptions.example(dryRun: true));
      expect(log.first, contains('Trying'));
      expect(calls.first, 'host (dry run)');
      expect(MaintainState.fileIn(runFolder()).existsSync(), isFalse);
      expect(log, isNot(contains(contains('--continue'))));
    });

    test('creates nothing when no repo is left', () async {
      final report = await run(
        options: MaintainOptions.example(repos: ['local_*']),
      );
      expect(started, isEmpty);
      expect(calls, ['host', 'prepare']);
      expect(log, contains(contains('No repo to maintain.')));
      expect(report.results.single.outcome, RepoOutcome.skipped);
      expect(runFolder().existsSync(), isFalse);
    });

    test('maintains with the real steps by default', () async {
      fixture.oceanRepo(
        'ggsuite',
        'gone',
        url: path.join(fixture.root.path, 'no_such_remote'),
      );
      final options = MaintainOptions.example(
        repos: ['gone'],
        dryRun: true,
        runId: 'test_${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(
        () => Directory(
          path.join(Directory.systemTemp.path, 'gg_maintain_${options.runId}'),
        ).deleteSync(recursive: true),
      );
      final report = await Maintainer().run(
        oceanPath: fixture.ocean.path,
        options: options,
        ggLog: log.add,
      );
      final result = report.results.single;
      expect(result.outcome, RepoOutcome.failed);
      expect(result.step, 'find the checkout');
      expect(log, contains(startsWith('Could not clone ggsuite/gone')));
    });

    test('example uses the real steps', () {
      expect(Maintainer.example, returnsNormally);
    });
  });
}
