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

void main() {
  group('RepoMaintainer', () {
    late GitFixture fixture;
    late List<String> log;

    setUp(() {
      fixture = GitFixture();
      log = [];
    });

    /// A checkout of a fresh remote [name] on the branch of the run.
    OceanRepo repoOf(String name, {Map<String, String>? files}) {
      final url = fixture.remote(name, files ?? GitFixture.dartPackage(name));
      final dir = Directory(path.join(fixture.root.path, 'run', name));
      dir.parent.createSync(recursive: true);
      GitFixture.git(dir.parent, ['clone', '-q', url, name]);
      GitFixture.git(dir, [
        'checkout',
        '-q',
        '-b',
        'maintain_2026_10_28_074200',
      ]);
      return OceanRepo.example(name: name, url: url, directory: dir);
    }

    String baseOf(OceanRepo repo) =>
        GitFixture.git(repo.directory, ['rev-parse', 'HEAD']);

    /// A task that changes the pubspec of the checkout.
    Future<void> touchPubspec({
      required Directory directory,
      required void Function(String) ggLog,
    }) async {
      final pubspec = File(path.join(directory.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst('>=3.0.0', '>=3.1.0'),
      );
    }

    Future<void> noop({
      required Directory directory,
      required void Function(String) ggLog,
    }) async {}

    RepoMaintainer maintainer({
      MaintainOptions? options,
      RepoTask? task,
      RepoTask? script,
      CommitStep? commit,
      MergeStep? merge,
    }) => RepoMaintainer(
      options: options ?? MaintainOptions.example(tasks: {MaintainTask.sdk}),
      tasks: {for (final t in MaintainTask.values) t: task ?? noop},
      script: script,
      commit:
          commit ??
          ({required directory, required ggLog, required message}) async =>
              log.add('commit: $message'),
      merge:
          merge ??
          ({
            required directory,
            required ggLog,
            required message,
            required resume,
          }) async => log.add('merge: $message${resume ? ', resumed' : ''}'),
    );

    Future<RepoResult> maintain(
      RepoMaintainer m,
      OceanRepo repo, {
      String? base,
      String? logPath,
      bool resume = false,
    }) => m.maintain(
      repo: repo,
      dir: repo.directory,
      base: base ?? baseOf(repo),
      ggLog: log.add,
      logPath: logPath,
      resume: resume,
    );

    group('maintain', () {
      test('runs the script after the SDK and before the DNA', () async {
        final options = MaintainOptions.example(
          tasks: {MaintainTask.dna, MaintainTask.sdk},
          script: '/x/migrate.dart',
        );
        final result = await maintain(
          maintainer(
            options: options,
            script: ({required directory, required ggLog}) async =>
                ggLog('script ran'),
          ),
          repoOf('gg_a'),
        );
        expect(result.outcome, RepoOutcome.unchanged);
        expect(log, [
          'Running --upgrade-sdk ...',
          'Running /x/migrate.dart ...',
          'script ran',
          'Running --upgrade-dna ...',
        ]);
      });

      test('runs the script last without the DNA', () async {
        final options = MaintainOptions.example(
          tasks: {MaintainTask.sdk},
          script: '/x/migrate.dart',
        );
        await maintain(
          maintainer(
            options: options,
            script: ({required directory, required ggLog}) async {},
          ),
          repoOf('gg_a'),
        );
        expect(log, [
          'Running --upgrade-sdk ...',
          'Running /x/migrate.dart ...',
        ]);
      });

      test('commits what the script changed with its name', () async {
        final options = MaintainOptions.example(
          tasks: {},
          script: '/x/migrate.dart',
        );
        final result = await maintain(
          maintainer(options: options, script: touchPubspec),
          repoOf('gg_a'),
        );
        expect(result.outcome, RepoOutcome.merged);
        expect(log, contains('commit: Run migrate.dart'));
      });

      test('fails the repo when the script fails', () async {
        final options = MaintainOptions.example(
          tasks: {},
          script: '/x/migrate.dart',
        );
        final result = await maintain(
          maintainer(
            options: options,
            script: ({required directory, required ggLog}) async =>
                throw Exception('broken'),
          ),
          repoOf('gg_a'),
        );
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'run migrate.dart');
      });

      test('runs the script of the options with real processes', () async {
        final script = File(path.join(fixture.root.path, 'hello.dart'))
          ..writeAsStringSync("void main() => print('hello');");
        final options = MaintainOptions.example(tasks: {}, script: script.path);
        final result = await maintain(
          RepoMaintainer(
            options: options,
            tasks: {for (final t in MaintainTask.values) t: noop},
          ),
          repoOf('gg_a'),
        );
        expect(result.outcome, RepoOutcome.unchanged);
        expect(log, contains('hello'));
      });

      test('reports an unchanged repo and keeps its checkout', () async {
        final repo = repoOf('gg_a');
        final result = await maintain(maintainer(), repo);
        expect(result.outcome, RepoOutcome.unchanged);
        expect(result.detail, '');
        expect(repo.directory.existsSync(), isTrue);
        expect(log, ['Running --upgrade-sdk ...']);
      });

      test('commits and merges a changed repo', () async {
        final repo = repoOf('gg_a');
        final result = await maintain(
          maintainer(task: touchPubspec),
          repo,
          logPath: 'gg_a.log',
        );
        expect(result.outcome, RepoOutcome.merged);
        expect(result.detail, 'pubspec.yaml');
        expect(result.logPath, 'gg_a.log');
        expect(log, [
          'Running --upgrade-sdk ...',
          'Changed: pubspec.yaml',
          'commit: Upgrade the SDK',
          'merge: Upgrade the SDK',
        ]);
      });

      test('resumes the merge when asked to', () async {
        await maintain(
          maintainer(task: touchPubspec),
          repoOf('gg_a'),
          resume: true,
        );
        expect(log.last, 'merge: Upgrade the SDK, resumed');
      });

      test('counts commits a task made, like the generated DNA', () async {
        final m = maintainer(
          task: ({required directory, required ggLog}) async {
            GitFixture.writeFiles(directory, {'CLAUDE.md': 'new'});
            GitFixture.git(directory, ['add', '.']);
            GitFixture.git(directory, ['commit', '-q', '-m', '#gg: DNA']);
          },
        );
        final result = await maintain(m, repoOf('gg_a'));
        expect(result.outcome, RepoOutcome.merged);
        expect(log, contains('Changed: 1 other file'));
      });

      test('counts the commits made since the base', () async {
        final repo = repoOf('gg_a');
        final base = baseOf(repo);
        GitFixture.writeFiles(repo.directory, {'fix.md': 'fixed by hand'});
        GitFixture.git(repo.directory, ['add', '.']);
        GitFixture.git(repo.directory, ['commit', '-q', '-m', 'Fix']);
        final result = await maintain(maintainer(), repo, base: base);
        expect(result.outcome, RepoOutcome.merged);
        expect(result.detail, '1 other file');
      });

      test('only reports the changes with --dry-run', () async {
        final m = maintainer(
          options: MaintainOptions.example(
            tasks: {MaintainTask.sdk},
            dryRun: true,
          ),
          task: ({required directory, required ggLog}) async {
            await touchPubspec(directory: directory, ggLog: ggLog);
            GitFixture.writeFiles(directory, {'doc/a.md': 'a'});
          },
        );
        final result = await maintain(m, repoOf('gg_a'));
        expect(result.outcome, RepoOutcome.changed);
        expect(result.detail, 'pubspec.yaml, 1 other file');
        expect(log, isNot(contains('commit: Upgrade the SDK')));
      });

      test('keeps the checkout of a failed step', () async {
        final m = maintainer(
          task: ({required directory, required ggLog}) async =>
              throw Exception('no network'),
        );
        final repo = repoOf('gg_a');
        final result = await maintain(m, repo, logPath: 'l');
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'upgrade-sdk');
        expect(result.detail, 'Exception: no network');
        expect(result.checkoutPath, repo.directory.path);
        expect(result.logPath, 'l');
        expect(repo.directory.existsSync(), isTrue);
        expect(log.last, 'Failed to upgrade-sdk: Exception: no network');
      });

      test('refuses a checkout on another branch', () async {
        final repo = repoOf('gg_a');
        GitFixture.git(repo.directory, ['checkout', '-q', 'main']);
        final result = await maintain(maintainer(task: touchPubspec), repo);
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'check the branch');
        expect(result.detail, contains('is on »main«'));
        expect(log, isNot(contains(startsWith('commit'))));
      });

      test('fails to install the dependencies of a broken pubspec', () async {
        final repo = repoOf(
          'gg_a',
          files: {'pubspec.yaml': 'name: gg_a\nenvironment: nonsense\n'},
        );
        final result = await maintain(maintainer(), repo);
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'install the dependencies');
      });

      test(
        'installs the npm dependencies of a TypeScript repo',
        () async {
          final repo = repoOf(
            'is-ready',
            files: {
              'package.json': '{"name": "is-ready", "version": "0.1.0"}',
              '.gitignore': 'node_modules/\n',
            },
          );
          final result = await maintain(maintainer(), repo);
          expect(result.outcome, RepoOutcome.unchanged, reason: result.detail);
        },
        // A real npm install, slow on a busy machine.
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test('reports the step of a failed merge', () async {
        final m = maintainer(
          task: touchPubspec,
          merge: ({
            required directory,
            required ggLog,
            required message,
            required resume,
          }) async => throw Exception('refused'),
        );
        final result = await maintain(m, repoOf('gg_a'));
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'merge');
      });
    });

    group('changesOf', () {
      test('ignores lock files and gg state, follows renames', () async {
        final repo = repoOf(
          'gg_a',
          files: {...GitFixture.dartPackage('gg_a'), 'old.md': 'old'},
        );
        final dir = repo.directory;
        final base = baseOf(repo);
        GitFixture.git(dir, ['mv', 'old.md', 'new.md']);
        GitFixture.writeFiles(dir, {
          'pubspec.lock': 'x',
          'sub/pnpm-lock.yaml': 'x',
          '.gg/gg.json': '{}',
          'a b.md': 'quoted',
        });
        final changes = await maintainer().changesOf(dir, base: base);
        expect(changes, ['a b.md', 'new.md']);
      });
    });

    test('summarize names the manifests and counts the rest', () {
      expect(RepoMaintainer.summarize(['a.md']), '1 other file');
      expect(
        RepoMaintainer.summarize(['package.json', 'a.md', 'b.md']),
        'package.json, 2 other files',
      );
      expect(RepoMaintainer.summarize(['pubspec.yaml']), 'pubspec.yaml');
    });

    test('example only logs', () async {
      final m = RepoMaintainer.example();
      expect(m.options.runId, '2026_10_28_074200');
      final result = await maintain(m, repoOf('gg_a'));
      expect(result.outcome, RepoOutcome.unchanged);
      expect(log, [
        'Running --upgrade-sdk ...',
        'upgrade-sdk',
        'Running --upgrade-deps ...',
        'upgrade-deps',
        'Running --upgrade-dna ...',
        'upgrade-dna',
      ]);
    });

    test('example logs the script', () async {
      final m = RepoMaintainer.example(
        options: MaintainOptions.example(tasks: {}, script: '/x/m.dart'),
      );
      await maintain(m, repoOf('gg_a'));
      expect(log, ['Running /x/m.dart ...', 'run']);
    });

    test('example steps commit and merge', () async {
      final m = RepoMaintainer.example(
        tasks: {for (final t in MaintainTask.values) t: touchPubspec},
      );
      await maintain(m, repoOf('gg_a'));
      expect(log.sublist(log.length - 2), ['commit', 'merge']);
    });

    test('creates the real tasks by default', () {
      expect(
        () => RepoMaintainer(options: MaintainOptions.example()),
        returnsNormally,
      );
    });
  });
}
