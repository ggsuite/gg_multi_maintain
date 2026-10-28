// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';

import '../backend/maintainer.dart';
import '../maintain_options.dart';

// #############################################################################
/// `gg do maintain`: runs maintenance tasks in all ocean repos.
///
/// At least one task flag is required. Every changed repo is committed and
/// published on its own with `gg one do publish`.
class DoMaintain extends Command<void> {
  /// Constructor
  DoMaintain({
    required this.ggLog,
    Maintainer? maintainer,
    this._workingDir,
    DateTime Function()? now,
  }) : _maintainer = maintainer ?? Maintainer(),
       _now = now ?? DateTime.now {
    _addArgs();
  }

  /// A command that logs nothing.
  factory DoMaintain.example({
    GgLog? ggLog,
    Maintainer? maintainer,
    String? workingDir,
  }) => DoMaintain(
    ggLog: ggLog ?? (_) {},
    maintainer: maintainer,
    workingDir: workingDir,
  );

  // ...........................................................................
  @override
  final name = 'maintain';

  @override
  final description =
      'Run maintenance tasks in all ocean repos in parallel and publish '
      'every changed repo.';

  @override
  String get invocation =>
      'gg do maintain '
      '(--upgrade-sdk | --upgrade-deps [--major] | --upgrade-dna | --all) '
      '[options]';

  /// The log function.
  final GgLog ggLog;

  // ...........................................................................
  @override
  Future<void> run() async {
    final options = optionsOf(argResults!);
    final oceanPath = WorkspaceUtils.defaultOceanWorkspacePath(
      workingDir: _workingDir ?? Directory.current.path,
    );
    if (!Directory(oceanPath).existsSync()) {
      throw UsageException(
        'Not inside a workspace: there is no .ocean folder.',
        usage,
      );
    }
    final report = await _maintainer.run(
      oceanPath: oceanPath,
      options: options,
      ggLog: ggLog,
    );
    if (report.hasProblems) {
      throw Exception('Maintenance failed for some repos, see above.');
    }
  }

  // ...........................................................................
  /// Turns the parsed arguments into options; throws on a wrong combination.
  MaintainOptions optionsOf(ArgResults args) {
    final all = args['all'] as bool;
    final tasks = {
      for (final task in MaintainTask.values)
        if (all || args[task.flag] as bool) task,
    };
    if (tasks.isEmpty) {
      throw UsageException(
        'Choose at least one task: '
        '${MaintainTask.values.map((t) => '--${t.flag}').join(', ')} '
        'or --all.',
        usage,
      );
    }
    final major = args['major'] as bool;
    if (major && !tasks.contains(MaintainTask.deps)) {
      throw UsageException('--major needs --upgrade-deps.', usage);
    }
    final jobs = int.tryParse(args['jobs'] as String);
    if (jobs == null || jobs < 1) {
      throw UsageException('--jobs needs a number of at least 1.', usage);
    }
    return MaintainOptions(
      tasks: tasks,
      runId: MaintainOptions.runIdOf(_now()),
      major: major,
      jobs: jobs,
      dryRun: args['dry-run'] as bool,
      orgs: args['org'] as List<String>,
      repos: args['repo'] as List<String>,
      versionIncrement: args['version-increment'] as String?,
      pana: args['pana'] as bool,
    );
  }

  // ...........................................................................
  final Maintainer _maintainer;
  final String? _workingDir;
  final DateTime Function() _now;

  // ...........................................................................
  void _addArgs() {
    argParser
      ..addFlag(
        MaintainTask.sdk.flag,
        negatable: false,
        help: 'Raise the SDK constraint to the installed Dart or Node version.',
      )
      ..addFlag(
        MaintainTask.deps.flag,
        negatable: false,
        help: 'Raise the dependencies to their newest compatible versions.',
      )
      ..addFlag(
        'major',
        negatable: false,
        help: 'With --upgrade-deps: also jump across major versions.',
      )
      ..addFlag(
        MaintainTask.dna.flag,
        negatable: false,
        help: 'Raise the DNA layers to their newest versions.',
      )
      ..addFlag('all', negatable: false, help: 'Run all tasks.')
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '4',
        help: 'How many repos are maintained at the same time.',
      )
      ..addMultiOption(
        'org',
        help: 'Only the repos of this organization. Repeat for more.',
      )
      ..addMultiOption(
        'repo',
        help:
            'Only the repos matching this name, e.g. gg_* or ggsuite/gg. '
            'Repeat for more.',
      )
      ..addOption(
        'version-increment',
        allowed: ['patch', 'minor', 'major'],
        help:
            'The version increment of every published repo. Default: minor '
            'when a dependency jumps a major version, else patch.',
      )
      ..addFlag(
        'pana',
        defaultsTo: true,
        help: 'Run pana before publishing a Dart package.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help:
            'Apply the tasks in the clones and report what would change, '
            'but neither commit nor publish.',
      );
  }
}
