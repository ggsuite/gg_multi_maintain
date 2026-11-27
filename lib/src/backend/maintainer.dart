// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import 'dag_scheduler.dart';
import 'dependency_order.dart';
import 'lane_log.dart';
import 'maintain_report.dart';
import 'maintain_state.dart';
import 'ocean_repo.dart';
import 'repo_host.dart';
import 'repo_maintainer.dart';
import 'repo_result.dart';
import 'repo_selection.dart';

// #############################################################################
/// Creates the maintainer of one run.
typedef RepoMaintainerFactory = RepoMaintainer Function(MaintainOptions);

/// Returns the host of a run, a different one for `--dry-run`.
typedef RepoHostFactory = RepoHost Function({required bool dryRun});

// #############################################################################
/// Maintains all selected ocean repos of a workspace.
///
/// A run works in a normal ticket, `maintain_<run id>`, holding every
/// selected repo: [RepoHost] syncs the ocean, creates the ticket and adds the
/// repos. The repos run in parallel, up to `--jobs` at a time, but a repo
/// only starts once every repo it depends on is merged or turned out
/// unchanged — so no repo is maintained on top of a broken one. A failed
/// repo blocks its dependents and nothing else.
///
/// A run that went well removes its ticket. A run with problems keeps it,
/// with [reportFile] — the summary for the developer, who reads it after a
/// run nobody watched — and the logs of the failed repos. The developer
/// fixes them in the ticket and calls [resume], which maintains what is not
/// done yet.
class Maintainer {
  /// Constructor
  Maintainer({
    this._selection = const RepoSelection(),
    DependencyOrder? order,
    RepoMaintainerFactory? repoMaintainer,
    RepoHostFactory? host,
  }) : _order = order ?? DependencyOrder(),
       _repoMaintainer =
           repoMaintainer ?? ((options) => RepoMaintainer(options: options)),
       _host = host ?? _defaultHost;

  /// A maintainer with the real steps.
  factory Maintainer.example() => Maintainer();

  // ...........................................................................
  /// Maintains the repos of [oceanPath] as [options] says and reports them.
  Future<MaintainReport> run({
    required String oceanPath,
    required MaintainOptions options,
    required GgLog ggLog,
  }) async {
    final workspacePath = path.dirname(oceanPath);
    final host = _host(dryRun: options.dryRun);
    await host.prepare(workspacePath: workspacePath, ggLog: ggLog);

    final (:selected, :skipped) = _selection.select(
      oceanPath: oceanPath,
      options: options,
    );
    final skippedResults = [
      for (final MapEntry(key: repo, value: reason) in skipped.entries)
        RepoResult(repo: repo, outcome: RepoOutcome.skipped, detail: reason),
    ];
    if (selected.isEmpty) {
      ggLog(yellow('No repo to maintain.'));
      return _report(skippedResults, ggLog);
    }

    final folder = host.folderOf(
      workspacePath: workspacePath,
      options: options,
    );
    final state = MaintainState(
      options: options,
      repos: [...selected, ...skipped.keys],
      dependencies: await _order.get(repos: selected),
      results: {for (final result in skippedResults) result.repo.key: result},
    );
    await host.create(folder: folder, options: options, ggLog: ggLog);
    _save(state, folder);
    await _add(host, folder, oceanPath, options, selected, ggLog);
    return _maintain(state, folder, host, ggLog, resume: false);
  }

  // ...........................................................................
  /// Continues the run of the ticket [folder]: adds the checkouts it lacks
  /// and maintains every repo that is neither merged nor unchanged yet.
  Future<MaintainReport> resume({
    required Directory folder,
    required String oceanPath,
    required GgLog ggLog,
  }) async {
    final state = MaintainState.load(folder);
    if (state == null) {
      throw Exception(
        '${folder.path} holds no run of gg do maintain to continue.',
      );
    }
    final host = _host(dryRun: false);
    final todo = state.todo;
    final checkouts = host.checkoutsOf(folder, todo);
    final missing = todo
        .where((repo) => !checkouts.containsKey(repo.key))
        .toList();
    if (missing.isNotEmpty) {
      await _add(host, folder, oceanPath, state.options, missing, ggLog);
    }
    return _maintain(state, folder, host, ggLog, resume: true);
  }

  // ...........................................................................
  /// The folder below the run folder that holds the logs of the repos.
  static const logFolder = '.gg/maintain_logs';

  /// The file in the run folder that reports a run with problems.
  static const reportFile = 'report.txt';

  // ...........................................................................
  final RepoSelection _selection;
  final DependencyOrder _order;
  final RepoMaintainerFactory _repoMaintainer;
  final RepoHostFactory _host;

  // ...........................................................................
  static RepoHost _defaultHost({required bool dryRun}) =>
      dryRun ? CloneRepoHost() : const TicketRepoHost();

  // ...........................................................................
  /// Adds [repos] to [folder]; a repo it could not add fails on its own.
  Future<void> _add(
    RepoHost host,
    Directory folder,
    String oceanPath,
    MaintainOptions options,
    List<OceanRepo> repos,
    GgLog ggLog,
  ) async {
    try {
      await host.add(
        folder: folder,
        oceanPath: oceanPath,
        options: options,
        repos: repos,
        ggLog: ggLog,
      );
    } catch (e) {
      ggLog(red('Could not add all repos: $e'));
    }
  }

  // ...........................................................................
  Future<MaintainReport> _maintain(
    MaintainState state,
    Directory folder,
    RepoHost host,
    GgLog ggLog, {
    required bool resume,
  }) async {
    final options = state.options;
    final todo = state.todo;
    _logPlan(todo, options, folder, ggLog, resume: resume);
    if (todo.isNotEmpty) {
      await _runAll(state, todo, folder, host, ggLog, resume: resume);
    }

    final report = _report(state.results.values, ggLog);
    if (report.hasProblems) {
      final file = File(path.join(folder.path, reportFile))
        ..writeAsStringSync(report.text(runId: options.runId));
      ggLog(darkGray('Report: ${file.path}'));
      if (!options.dryRun) {
        ggLog(
          yellow(
            'Fix the failed repos in ${folder.path}, then run '
            'gg do maintain --continue -i ${path.basename(folder.path)}',
          ),
        );
      }
    } else {
      await host.close(folder: folder, ggLog: ggLog);
    }
    return report;
  }

  // ...........................................................................
  MaintainReport _report(Iterable<RepoResult> results, GgLog ggLog) {
    final report = MaintainReport(results: results.toList());
    ggLog('');
    report.lines().forEach(ggLog);
    return report;
  }

  // ...........................................................................
  void _save(MaintainState state, Directory folder) {
    if (!state.options.dryRun) state.save(folder);
  }

  // ...........................................................................
  Future<void> _runAll(
    MaintainState state,
    List<OceanRepo> todo,
    Directory folder,
    RepoHost host,
    GgLog ggLog, {
    required bool resume,
  }) async {
    final options = state.options;
    final repos = {for (final repo in todo) repo.key: repo};
    final keys = repos.keys.toSet();
    final checkouts = host.checkoutsOf(folder, todo);
    final maintainer = _repoMaintainer(options);

    void finish(RepoResult result) {
      state.results[result.repo.key] = result;
      _save(state, folder);
    }

    await DagScheduler(jobs: options.jobs).run(
      // Done repos are no longer waited for.
      dependencies: {
        for (final key in repos.keys)
          key: {...?state.dependencies[key]}.intersection(keys),
      },
      task: (key) async {
        final repo = repos[key]!;
        final logFile = File(
          path.join(folder.path, logFolder, repo.org, '${repo.name}.log'),
        )..parent.createSync(recursive: true);
        if (logFile.existsSync()) logFile.deleteSync();
        final laneLog = LaneLog(prefix: key, ggLog: ggLog, file: logFile).call;

        final dir = checkouts[key];
        final result =
            await _startOf(state, host, folder, repo, dir, laneLog) ??
            await maintainer.maintain(
              repo: repo,
              dir: dir!,
              base: state.bases[key]!,
              ggLog: laneLog,
              logPath: logFile.path,
              resume: resume,
            );
        if (result.outcome != RepoOutcome.failed && logFile.existsSync()) {
          logFile.deleteSync();
        }
        finish(result);
        LaneLog(prefix: key, ggLog: ggLog)(
          _color(result)(result.outcome.title),
        );
        return result.outcome.letsDependentsRun;
      },
      onBlocked: (key, failed) => finish(
        RepoResult(
          repo: repos[key]!,
          outcome: RepoOutcome.blocked,
          detail: 'waits for ${failed.join(', ')}',
        ),
      ),
    );
  }

  // ...........................................................................
  /// Notes the commit the checkout [dir] of [repo] starts from, once per
  /// run; returns the failure when there is no usable checkout.
  Future<RepoResult?> _startOf(
    MaintainState state,
    RepoHost host,
    Directory folder,
    OceanRepo repo,
    Directory? dir,
    GgLog ggLog,
  ) async {
    RepoResult failed(String detail) {
      ggLog('Failed to find the checkout: $detail');
      return RepoResult(
        repo: repo,
        outcome: RepoOutcome.failed,
        step: 'find the checkout',
        detail: detail,
      );
    }

    if (dir == null) return failed('${folder.path} holds no ${repo.key}');
    if (state.bases.containsKey(repo.key)) return null;
    try {
      state.bases[repo.key] = (await host.shell.run('git', [
        'rev-parse',
        'HEAD',
      ], directory: dir)).trim();
      return null;
    } catch (e) {
      return failed('$e');
    }
  }

  // ...........................................................................
  void _logPlan(
    List<OceanRepo> todo,
    MaintainOptions options,
    Directory folder,
    GgLog ggLog, {
    required bool resume,
  }) {
    final flags = [
      ...MaintainTask.values
          .where(options.tasks.contains)
          .map((task) => '--${task.flag}'),
      if (options.script != null) '--run ${options.script}',
    ].join(' ');
    final verb = options.dryRun
        ? 'Trying'
        : resume
        ? 'Continuing'
        : 'Running';
    ggLog(
      yellow(
        '$verb $flags in ${todo.length} repos, ${options.jobs} at a time.',
      ),
    );
    ggLog(darkGray('Working folder: ${folder.path}'));
  }

  // ...........................................................................
  String Function(Object) _color(RepoResult result) =>
      result.outcome.letsDependentsRun ? green : red;
}
