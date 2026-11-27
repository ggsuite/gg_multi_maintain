// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// #############################################################################
/// Records the options instead of maintaining anything.
class _RecordingMaintainer extends Maintainer {
  _RecordingMaintainer({this.problems = false});

  final bool problems;
  MaintainOptions? options;
  String? oceanPath;
  Directory? resumed;

  @override
  Future<MaintainReport> resume({
    required Directory folder,
    required String oceanPath,
    required void Function(String) ggLog,
  }) async {
    resumed = folder;
    return const MaintainReport(results: []);
  }

  @override
  Future<MaintainReport> run({
    required String oceanPath,
    required MaintainOptions options,
    required void Function(String) ggLog,
  }) async {
    this.options = options;
    this.oceanPath = oceanPath;
    ggLog('maintained');
    return MaintainReport(
      results: [
        if (problems)
          RepoResult.example(outcome: RepoOutcome.failed, detail: 'x'),
      ],
    );
  }
}

void main() {
  group('DoMaintain', () {
    late Directory workspace;
    late _RecordingMaintainer maintainer;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('do_maintain_test');
      Directory(path.join(workspace.path, '.ocean')).createSync();
      addTearDown(() => workspace.deleteSync(recursive: true));
      maintainer = _RecordingMaintainer();
    });

    Future<void> run(
      List<String> args, {
      Maintainer? using,
      String? workingDir,
    }) {
      final runner = CommandRunner<void>('gg', 'test')
        ..addCommand(
          DoMaintain(
            ggLog: (_) {},
            maintainer: using ?? maintainer,
            workingDir: workingDir ?? workspace.path,
            now: () => DateTime(2026, 10, 28, 9, 5, 1),
          ),
        );
      return runner.run(['maintain', ...args]);
    }

    Matcher usageError(String text) => throwsA(
      isA<UsageException>().having((e) => e.message, 'message', contains(text)),
    );

    test('runs the chosen task with the defaults', () async {
      await run(['--upgrade-sdk']);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.sdk});
      expect(options.runId, '2026_10_28_090501');
      expect(options.major, isFalse);
      expect(options.jobs, 4);
      expect(options.dryRun, isFalse);
      expect(options.orgs, isEmpty);
      expect(options.repos, isEmpty);
      expect(maintainer.oceanPath, path.join(workspace.path, '.ocean'));
    });

    test('takes every option', () async {
      await run([
        '--upgrade-deps',
        '--major',
        '--upgrade-dna',
        '-j',
        '8',
        '--org',
        'ggsuite',
        '--repo',
        'gg_*',
        '--repo',
        'helix',
        '--dry-run',
      ]);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.deps, MaintainTask.dna});
      expect(options.major, isTrue);
      expect(options.jobs, 8);
      expect(options.orgs, ['ggsuite']);
      expect(options.repos, ['gg_*', 'helix']);
      expect(options.dryRun, isTrue);
    });

    test('--nightly upgrades the dependencies across major versions', () async {
      await run(['--nightly']);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.deps});
      expect(options.major, isTrue);
      expect(options.dryRun, isFalse);
    });

    test('--nightly goes with other tasks', () async {
      await run(['--nightly', '--upgrade-dna']);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.deps, MaintainTask.dna});
      expect(options.major, isTrue);
    });

    test('--all runs every task', () async {
      await run(['--all']);
      expect(maintainer.options!.tasks, MaintainTask.values.toSet());
    });

    test('--run runs a script alone, by its absolute path', () async {
      File(path.join(workspace.path, 'migrate.dart')).writeAsStringSync('');
      await run(['--run', 'migrate.dart']);
      final options = maintainer.options!;
      expect(options.tasks, isEmpty);
      expect(options.script, path.join(workspace.path, 'migrate.dart'));
    });

    test('--run goes with the task flags', () async {
      final script = File(path.join(workspace.path, 'migrate.sh'))
        ..writeAsStringSync('');
      await run(['--upgrade-dna', '--run', script.path]);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.dna});
      expect(options.script, script.path);
    });

    test('--run needs an existing script', () async {
      await expectLater(
        run(['--run', 'missing.dart']),
        usageError('The script missing.dart does not exist'),
      );
    });

    test('needs a task', () async {
      await expectLater(run([]), usageError('Choose at least one task'));
    });

    test('needs --upgrade-deps for --major', () async {
      await expectLater(
        run(['--upgrade-sdk', '--major']),
        usageError('--major needs --upgrade-deps'),
      );
    });

    test('needs --continue for --ticket', () async {
      await expectLater(
        run(['--upgrade-sdk', '-i', 'maintain_1']),
        usageError('--ticket goes with --continue only'),
      );
    });

    test('needs a positive number of jobs', () async {
      await expectLater(
        run(['--upgrade-sdk', '--jobs', '0']),
        usageError('--jobs needs a number'),
      );
      await expectLater(
        run(['--upgrade-sdk', '--jobs', 'many']),
        usageError('--jobs needs a number'),
      );
    });

    test('needs a workspace', () async {
      final elsewhere = Directory.systemTemp.createTempSync('no_workspace');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      await expectLater(
        run(['--upgrade-sdk'], workingDir: elsewhere.path),
        usageError('Not inside a workspace'),
      );
    });

    test('fails when a repo failed', () async {
      await expectLater(
        run(['--upgrade-sdk'], using: _RecordingMaintainer(problems: true)),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('Maintenance failed for some repos'),
          ),
        ),
      );
    });

    group('--continue', () {
      Directory ticket(String name, {bool withState = true}) {
        final dir = Directory(path.join(workspace.path, name))..createSync();
        File(path.join(dir.path, 'ticket.json')).writeAsStringSync('{}');
        if (withState) MaintainState.example().save(dir);
        return dir;
      }

      test('takes the ticket of -i', () async {
        final t = ticket('maintain_1');
        ticket('maintain_2');
        await run(['--continue', '-i', 'maintain_1']);
        expect(maintainer.resumed!.path, t.path);
        expect(maintainer.options, isNull);
      });

      test('takes the ticket it runs in', () async {
        final t = ticket('maintain_1');
        ticket('maintain_2');
        final repo = Directory(path.join(t.path, 'gg_a'))..createSync();
        await run(['--continue'], workingDir: repo.path);
        expect(maintainer.resumed!.path, t.path);
      });

      test('else takes the latest maintenance ticket', () async {
        ticket('maintain_2026_10_01_000000');
        final latest = ticket('maintain_2026_11_01_000000');
        ticket('maintain_2026_12_01_000000', withState: false);
        ticket('other');
        await run(['--continue']);
        expect(maintainer.resumed!.path, latest.path);
      });

      test('needs a run to continue', () async {
        ticket('maintain_x', withState: false);
        await expectLater(
          run(['--continue']),
          usageError('There is no run of gg do maintain to continue'),
        );
        await expectLater(
          run(['--continue', '-i', 'maintain_x']),
          usageError('maintain_x is no ticket of gg do maintain'),
        );
      });

      test('refuses the options of a new run', () async {
        await expectLater(
          run(['--continue', '--upgrade-sdk', '-j', '2']),
          usageError('drop --upgrade-sdk, --jobs'),
        );
      });
    });

    test('example logs nowhere', () async {
      final runner = CommandRunner<void>('gg', 'test')
        ..addCommand(
          DoMaintain.example(
            maintainer: maintainer,
            workingDir: workspace.path,
          ),
        );
      await runner.run(['maintain', '--upgrade-dna']);
      expect(maintainer.options!.tasks, {MaintainTask.dna});
    });

    test('describes itself', () {
      final command = DoMaintain.example();
      expect(command.name, 'maintain');
      expect(
        command.description,
        contains('merge every changed repo into main'),
      );
      expect(command.invocation, contains('gg do maintain (--upgrade-sdk'));
      expect(command.invocation, contains('--nightly'));
      expect(command.invocation, contains('--continue [-i <ticket>]'));
      final runner = CommandRunner<void>('gg', 'test')..addCommand(command);
      expect(runner.commands['maintain'], command);
    });
  });
}
