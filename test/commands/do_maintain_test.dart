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
      expect(options.versionIncrement, isNull);
      expect(options.pana, isTrue);
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
        '--version-increment',
        'minor',
        '--no-pana',
        '--dry-run',
      ]);
      final options = maintainer.options!;
      expect(options.tasks, {MaintainTask.deps, MaintainTask.dna});
      expect(options.major, isTrue);
      expect(options.jobs, 8);
      expect(options.orgs, ['ggsuite']);
      expect(options.repos, ['gg_*', 'helix']);
      expect(options.versionIncrement, 'minor');
      expect(options.pana, isFalse);
      expect(options.dryRun, isTrue);
    });

    test('--all runs every task', () async {
      await run(['--all']);
      expect(maintainer.options!.tasks, MaintainTask.values.toSet());
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
      expect(command.description, contains('publish every changed repo'));
      expect(command.invocation, contains('gg do maintain (--upgrade-sdk'));
      final runner = CommandRunner<void>('gg', 'test')..addCommand(command);
      expect(runner.commands['maintain'], command);
    });
  });
}
