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
    late Directory runDir;
    late List<String> log;

    setUp(() {
      fixture = GitFixture();
      runDir = Directory(path.join(fixture.root.path, 'run'));
      log = [];
    });

    OceanRepo repoOf(String name, {Map<String, String>? files}) =>
        OceanRepo.example(
          name: name,
          url: fixture.remote(name, files ?? GitFixture.dartPackage(name)),
        );

    /// A task that changes the pubspec of the clone.
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
      IsPublishedStep? isPublished,
      CommitStep? commit,
      MergeStep? merge,
    }) => RepoMaintainer(
      options: options ?? MaintainOptions.example(tasks: {MaintainTask.sdk}),
      runDir: runDir,
      tasks: {for (final t in MaintainTask.values) t: task ?? noop},
      isPublished:
          isPublished ?? ({required directory, required ggLog}) async => true,
      commit:
          commit ??
          ({required directory, required ggLog, required message}) async =>
              log.add('commit: $message'),
      merge:
          merge ??
          ({required directory, required ggLog, required message}) async =>
              log.add('merge: $message'),
    );

    group('maintain', () {
      test('reports an unchanged repo and deletes its clone', () async {
        final m = maintainer();
        final repo = repoOf('gg_a');
        final result = await m.maintain(repo: repo, ggLog: log.add);
        expect(result.outcome, RepoOutcome.unchanged);
        expect(result.detail, '');
        expect(m.cloneDirOf(repo).existsSync(), isFalse);
        expect(log, ['Running --upgrade-sdk ...']);
      });

      test('commits and merges a changed repo', () async {
        final m = maintainer(task: touchPubspec);
        final repo = repoOf('gg_a');
        final result = await m.maintain(
          repo: repo,
          ggLog: log.add,
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
        expect(m.cloneDirOf(repo).existsSync(), isFalse);
      });

      test('works on the branch of the run', () async {
        String? branch;
        final m = maintainer(
          task: touchPubspec,
          commit:
              ({required directory, required ggLog, required message}) async {
                branch = GitFixture.git(directory, [
                  'branch',
                  '--show-current',
                ]);
              },
        );
        await m.maintain(repo: repoOf('gg_a'), ggLog: log.add);
        expect(branch, 'maintain_2026_10_28_074200');
      });

      test('counts commits a task made, like the generated DNA', () async {
        final m = maintainer(
          task: ({required directory, required ggLog}) async {
            GitFixture.writeFiles(directory, {'CLAUDE.md': 'new'});
            GitFixture.git(directory, ['add', '.']);
            GitFixture.git(directory, ['commit', '-q', '-m', '#gg: DNA']);
          },
        );
        final result = await m.maintain(repo: repoOf('gg_a'), ggLog: log.add);
        expect(result.outcome, RepoOutcome.merged);
        expect(log, contains('Changed: 1 other file'));
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
        final repo = repoOf('gg_a');
        final result = await m.maintain(repo: repo, ggLog: log.add);
        expect(result.outcome, RepoOutcome.changed);
        expect(result.detail, 'pubspec.yaml, 1 other file');
        expect(log, isNot(contains('commit: Upgrade the SDK')));
        expect(m.cloneDirOf(repo).existsSync(), isFalse);
      });

      test('skips a package that was never published', () async {
        final m = maintainer(
          isPublished: ({required directory, required ggLog}) async => false,
        );
        final repo = repoOf('gg_a');
        final result = await m.maintain(repo: repo, ggLog: log.add);
        expect(result.outcome, RepoOutcome.skipped);
        expect(result.detail, contains('publish the first version by hand'));
        expect(m.cloneDirOf(repo).existsSync(), isFalse);
      });

      test('keeps the clone of a failed step', () async {
        final m = maintainer(
          task: ({required directory, required ggLog}) async =>
              throw Exception('no network'),
        );
        final repo = repoOf('gg_a');
        final result = await m.maintain(
          repo: repo,
          ggLog: log.add,
          logPath: 'l',
        );
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'upgrade-sdk');
        expect(result.detail, 'Exception: no network');
        expect(result.clonePath, m.cloneDirOf(repo).path);
        expect(result.logPath, 'l');
        expect(m.cloneDirOf(repo).existsSync(), isTrue);
        expect(log.last, 'Failed to upgrade-sdk: Exception: no network');
      });

      test('fails in the clone step for a wrong url', () async {
        final m = maintainer();
        final result = await m.maintain(
          repo: OceanRepo.example(url: path.join(fixture.root.path, 'none')),
          ggLog: log.add,
        );
        expect(result.outcome, RepoOutcome.failed);
        expect(result.step, 'clone');
      });

      test(
        'installs the npm dependencies of a TypeScript repo',
        () async {
          final m = maintainer();
          final repo = repoOf(
            'is-ready',
            files: {
              'package.json': '{"name": "is-ready", "version": "0.1.0"}',
              '.gitignore': 'node_modules/\n',
            },
          );
          final result = await m.maintain(repo: repo, ggLog: log.add);
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
          }) async => throw Exception('refused'),
        );
        final result = await m.maintain(repo: repoOf('gg_a'), ggLog: (_) {});
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
        final dir = Directory(path.join(fixture.root.path, 'clone'));
        GitFixture.git(fixture.root, ['clone', '-q', repo.url, dir.path]);
        final base = GitFixture.git(dir, ['rev-parse', 'HEAD']);
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

    test('example works in the temp folder', () {
      expect(RepoMaintainer.example().runDir.path, Directory.systemTemp.path);
    });

    test('example only logs', () async {
      final m = RepoMaintainer.example(runDir: runDir);
      expect(m.options.runId, '2026_10_28_074200');
      final repo = repoOf('gg_a');
      final result = await m.maintain(repo: repo, ggLog: log.add);
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

    test('example steps commit and merge', () async {
      final m = RepoMaintainer.example(
        runDir: runDir,
        tasks: {for (final t in MaintainTask.values) t: touchPubspec},
      );
      await m.maintain(repo: repoOf('gg_a'), ggLog: log.add);
      expect(log.sublist(log.length - 2), ['commit', 'merge']);
    });

    test('creates the real tasks by default', () {
      expect(
        () =>
            RepoMaintainer(options: MaintainOptions.example(), runDir: runDir),
        returnsNormally,
      );
    });
  });
}
