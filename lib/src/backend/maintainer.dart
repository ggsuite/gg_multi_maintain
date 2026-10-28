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
import 'ocean_repo.dart';
import 'repo_maintainer.dart';
import 'repo_result.dart';
import 'repo_selection.dart';

// #############################################################################
/// Creates the maintainer of one run.
typedef RepoMaintainerFactory = RepoMaintainer Function(
  MaintainOptions options,
  Directory runDir,
);

// #############################################################################
/// Maintains all selected ocean repos of a workspace.
///
/// The repos run in parallel, up to `--jobs` at a time, but a repo only
/// starts once every repo it depends on is published or turned out
/// unchanged — so an upgrade always sees the versions this run released.
/// A failed repo blocks its dependents and nothing else.
///
/// Everything happens below `<workspace>/.maintain/<run id>/<org>/<repo>`.
/// The folder only keeps what failed: the clone and its log.
class Maintainer {
  /// Constructor
  Maintainer({
    this._selection = const RepoSelection(),
    DependencyOrder? order,
    RepoMaintainerFactory? repoMaintainer,
  }) : _order = order ?? DependencyOrder(),
       _repoMaintainer =
           repoMaintainer ??
           ((options, runDir) =>
               RepoMaintainer(options: options, runDir: runDir));

  /// A maintainer with the real steps.
  factory Maintainer.example() => Maintainer();

  // ...........................................................................
  /// Maintains the repos of [oceanPath] as [options] says and reports them.
  Future<MaintainReport> run({
    required String oceanPath,
    required MaintainOptions options,
    required GgLog ggLog,
  }) async {
    final (:selected, :skipped) = await _selection.select(
      oceanPath: oceanPath,
      options: options,
    );
    final runDir = Directory(
      path.join(path.dirname(oceanPath), maintainFolder, options.runId),
    );
    final results = <String, RepoResult>{
      for (final MapEntry(key: repo, value: reason) in skipped.entries)
        repo.key: RepoResult(
          repo: repo,
          outcome: RepoOutcome.skipped,
          detail: reason,
        ),
    };

    _logPlan(selected, options, runDir, ggLog);
    if (selected.isNotEmpty) {
      await _runAll(selected, options, runDir, results, ggLog);
    }

    _cleanUp(runDir, results.values);
    final report = MaintainReport(results: results.values.toList());
    ggLog('');
    report.lines().forEach(ggLog);
    return report;
  }

  // ...........................................................................
  /// The folder below the workspace root that holds the runs.
  static const maintainFolder = '.maintain';

  // ...........................................................................
  final RepoSelection _selection;
  final DependencyOrder _order;
  final RepoMaintainerFactory _repoMaintainer;

  // ...........................................................................
  Future<void> _runAll(
    List<OceanRepo> selected,
    MaintainOptions options,
    Directory runDir,
    Map<String, RepoResult> results,
    GgLog ggLog,
  ) async {
    final repos = {for (final repo in selected) repo.key: repo};
    final dependencies = await _order.get(repos: selected);
    final maintainer = _repoMaintainer(options, runDir);

    await DagScheduler(jobs: options.jobs).run(
      dependencies: dependencies,
      task: (key) async {
        final repo = repos[key]!;
        final logFile = File('${maintainer.cloneDirOf(repo).path}.log');
        logFile.parent.createSync(recursive: true);
        final result = await maintainer.maintain(
          repo: repo,
          ggLog: LaneLog(prefix: key, ggLog: ggLog, file: logFile).call,
          logPath: logFile.path,
        );
        results[key] = result;
        LaneLog(prefix: key, ggLog: ggLog)(
          _color(result)(result.outcome.title),
        );
        return result.outcome.letsDependentsRun;
      },
      onBlocked: (key, failed) {
        results[key] = RepoResult(
          repo: repos[key]!,
          outcome: RepoOutcome.blocked,
          detail: 'waits for ${failed.join(', ')}',
        );
      },
    );
  }

  // ...........................................................................
  void _logPlan(
    List<OceanRepo> selected,
    MaintainOptions options,
    Directory runDir,
    GgLog ggLog,
  ) {
    final flags = MaintainTask.values
        .where(options.tasks.contains)
        .map((task) => '--${task.flag}')
        .join(' ');
    ggLog(
      yellow(
        '${options.dryRun ? 'Trying' : 'Running'} $flags in '
        '${selected.length} repos, ${options.jobs} at a time.',
      ),
    );
    ggLog(darkGray('Working folder: ${runDir.path}'));
  }

  // ...........................................................................
  /// Deletes the logs of the repos that went well and the empty folders.
  void _cleanUp(Directory runDir, Iterable<RepoResult> results) {
    for (final result in results) {
      final log = result.logPath;
      if (log == null || result.outcome == RepoOutcome.failed) continue;
      final file = File(log);
      if (file.existsSync()) file.deleteSync();
    }
    _deleteEmpty(runDir);
    _deleteEmpty(runDir.parent);
  }

  // ...........................................................................
  void _deleteEmpty(Directory dir) {
    if (!dir.existsSync()) return;
    for (final child in dir.listSync().whereType<Directory>()) {
      _deleteEmpty(child);
    }
    if (dir.listSync().isEmpty) dir.deleteSync();
  }

  // ...........................................................................
  String Function(Object) _color(RepoResult result) =>
      result.outcome.letsDependentsRun ? green : red;
}
