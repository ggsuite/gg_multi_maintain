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
import 'package:path/path.dart' as path;

import '../backend/maintain_state.dart';
import '../backend/maintainer.dart';
import '../maintain_options.dart';

// #############################################################################
/// `gg do maintain`: runs maintenance tasks in all ocean repos.
///
/// At least one task flag is required. The run syncs the ocean, creates the
/// ticket `maintain_<run id>` with every repo and commits and merges every
/// changed repo into its main branch with `gg one do publish --merge-only` —
/// nothing is released to a registry. A release goes through a normal ticket
/// and its review.
///
/// A run with problems keeps its ticket. `--continue` goes on with it after
/// the failed repos were fixed there: the ticket of `-i`, the ticket the
/// command runs in, or else the latest maintenance ticket.
///
/// `--nightly` is the run a computer of its own starts every night: it
/// upgrades the dependencies of every repo across major versions
/// (`--upgrade-deps --major`). A repo that breaks stops the repos that
/// depend on it, and the run writes `report.txt` into its run folder.
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
      'Run maintenance tasks in all ocean repos in parallel and merge '
      'every changed repo into main, without publishing.';

  @override
  String get invocation =>
      'gg do maintain '
      '(--upgrade-sdk | --upgrade-deps [--major] | --upgrade-dna | --all | '
      '--nightly) [options]\n'
      '       gg do maintain --continue [-i <ticket>]';

  /// The log function.
  final GgLog ggLog;

  // ...........................................................................
  @override
  Future<void> run() async {
    final args = argResults!;
    final workingDir = _workingDir ?? Directory.current.path;
    final oceanPath = WorkspaceUtils.defaultOceanWorkspacePath(
      workingDir: workingDir,
    );
    if (!Directory(oceanPath).existsSync()) {
      throw UsageException(
        'Not inside a workspace: there is no .ocean folder.',
        usage,
      );
    }
    final report = args['continue'] as bool
        ? await _maintainer.resume(
            folder: ticketToContinue(args, oceanPath, workingDir),
            oceanPath: oceanPath,
            ggLog: ggLog,
          )
        : await _maintainer.run(
            oceanPath: oceanPath,
            options: optionsOf(args),
            ggLog: ggLog,
          );
    if (report.hasProblems) {
      throw Exception('Maintenance failed for some repos, see above.');
    }
  }

  // ...........................................................................
  /// Returns the ticket `--continue` goes on with; throws when there is none
  /// or when other options were given.
  Directory ticketToContinue(
    ArgResults args,
    String oceanPath,
    String workingDir,
  ) {
    final given = args.options.where(
      (option) => !_continueOptions.contains(option) && args.wasParsed(option),
    );
    if (given.isNotEmpty) {
      throw UsageException(
        '--continue takes the options of the run it continues, '
        'drop --${given.join(', --')}.',
        usage,
      );
    }
    final root = path.dirname(oceanPath);
    final id = args['ticket'] as String?;
    if (id != null) {
      final ticket = WorkspaceUtils.existingTicketDir(
        rootPath: root,
        ticketName: id,
      );
      if (ticket == null || !MaintainState.existsIn(ticket)) {
        throw UsageException('$id is no ticket of gg do maintain.', usage);
      }
      return ticket;
    }
    final current = WorkspaceUtils.detectTicketPath(workingDir);
    if (current != null && MaintainState.existsIn(Directory(current))) {
      return Directory(current);
    }
    final tickets = WorkspaceUtils.ticketDirs(root).where(
      (dir) =>
          path.basename(dir.path).startsWith('maintain_') &&
          MaintainState.existsIn(dir),
    );
    if (tickets.isEmpty) {
      throw UsageException(
        'There is no run of gg do maintain to continue.',
        usage,
      );
    }
    return tickets.last;
  }

  // ...........................................................................
  /// Turns the parsed arguments into options; throws on a wrong combination.
  MaintainOptions optionsOf(ArgResults args) {
    if (args.wasParsed('ticket')) {
      throw UsageException('--ticket goes with --continue only.', usage);
    }
    final all = args['all'] as bool;
    final nightly = args['nightly'] as bool;
    final tasks = {
      for (final task in MaintainTask.values)
        if (all || args[task.flag] as bool) task,
      if (nightly) MaintainTask.deps,
    };
    if (tasks.isEmpty) {
      throw UsageException(
        'Choose at least one task: '
        '${MaintainTask.values.map((t) => '--${t.flag}').join(', ')}, '
        '--all or --nightly.',
        usage,
      );
    }
    final major = nightly || args['major'] as bool;
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
    );
  }

  // ...........................................................................
  final Maintainer _maintainer;
  final String? _workingDir;
  final DateTime Function() _now;

  static const _continueOptions = {'continue', 'ticket'};

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
      ..addFlag(
        'nightly',
        negatable: false,
        help:
            'The nightly build: --upgrade-deps --major. A repo that breaks '
            'stops its dependents; the run folder gets a report.txt.',
      )
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
      ..addFlag(
        'continue',
        negatable: false,
        help:
            'Go on with a run that had problems, in its ticket, once the '
            'failed repos are fixed there.',
      )
      ..addOption(
        'ticket',
        abbr: 'i',
        help:
            'With --continue: the ticket of the run. Default: the ticket '
            'the command runs in, else the latest maintenance ticket.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help:
            'Apply the tasks in temporary clones and report what would '
            'change, but create no ticket and neither commit nor merge.',
      );
  }
}
