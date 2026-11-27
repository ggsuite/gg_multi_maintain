// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import '../tasks/upgrade_deps.dart';
import '../tasks/upgrade_dna.dart';
import '../tasks/run_script.dart';
import '../tasks/upgrade_sdk.dart';
import 'ocean_repo.dart';
import 'repo_result.dart';
import 'shell.dart';

// #############################################################################
/// Applies one maintenance task to a checkout.
typedef RepoTask = Future<void> Function({
  required Directory directory,
  required GgLog ggLog,
});

/// Commits the maintained checkout, like `gg one do commit`.
typedef CommitStep = Future<void> Function({
  required Directory directory,
  required GgLog ggLog,
  required String message,
});

/// Merges the committed checkout into the main branch without releasing it,
/// like `gg one do publish --merge-only`; [resume] continues an unfinished
/// merge.
typedef MergeStep = Future<void> Function({
  required Directory directory,
  required GgLog ggLog,
  required String message,
  required bool resume,
});

// #############################################################################
/// Maintains one repo in its checkout of the run.
///
/// The checkout sits on the run's feature branch already (see `RepoHost`):
///
/// 1. make sure the checkout is on that branch, install the dependencies
/// 2. run the selected tasks: SDK, dependencies, the script, DNA
/// 3. stop as unchanged when, since the commit the run started from, only
///    lock files or gg's own state changed
/// 4. commit with `gg one do commit`, which runs all checks and tests
/// 5. merge into the main branch with `gg one do publish --merge-only`: no
///    version increase, no upload, no tag. The changes wait below
///    `## Unreleased` until a ticket releases the repo
///
/// Every step can run again: a repo that failed is maintained once more in
/// the same checkout, with what the developer fixed there.
class RepoMaintainer {
  /// Constructor
  RepoMaintainer({
    required this.options,
    Shell shell = const Shell(),
    Map<MaintainTask, RepoTask>? tasks,
    RepoTask? script,
    CommitStep? commit,
    MergeStep? merge,
  }) : _shell = shell,
       _tasks = tasks ?? _defaultTasks(options, shell),
       _script =
           script ??
           (options.script == null
               ? null
               : RunScript(script: options.script!, shell: shell).apply),
       _commit = commit ?? _defaultCommit,
       _merge = merge ?? _defaultMerge;

  /// A maintainer whose steps only log.
  factory RepoMaintainer.example({
    MaintainOptions? options,
    Shell? shell,
    Map<MaintainTask, RepoTask>? tasks,
    RepoTask? script,
    CommitStep? commit,
    MergeStep? merge,
  }) => RepoMaintainer(
    options: options ?? MaintainOptions.example(),
    shell: shell ?? const Shell(),
    script:
        script ?? ({required directory, required ggLog}) async => ggLog('run'),
    tasks:
        tasks ??
        {
          for (final task in MaintainTask.values)
            task: ({required directory, required ggLog}) async =>
                ggLog(task.flag),
        },
    commit:
        commit ??
        ({required directory, required ggLog, required message}) async =>
            ggLog('commit'),
    merge:
        merge ??
        ({
          required directory,
          required ggLog,
          required message,
          required resume,
        }) async => ggLog('merge'),
  );

  // ...........................................................................
  /// What to do.
  final MaintainOptions options;

  // ...........................................................................
  /// Maintains [repo] in its checkout [dir] and reports how it ended.
  ///
  /// [base] is the commit the run started from; [resume] continues a merge
  /// an earlier run left unfinished.
  Future<RepoResult> maintain({
    required OceanRepo repo,
    required Directory dir,
    required String base,
    required GgLog ggLog,
    String? logPath,
    bool resume = false,
  }) async {
    var step = 'check the branch';
    RepoResult result(RepoOutcome outcome, String detail, {String? step}) =>
        RepoResult(
          repo: repo,
          outcome: outcome,
          detail: detail,
          step: step,
          checkoutPath: step == null ? null : dir.path,
          logPath: logPath,
        );

    // A checkout that changed since the base was maintained before: the
    // script ran already and is not run twice, e.g. by --continue.
    var scriptRan = false;
    Future<void> runScript() async {
      if (options.script == null) return;
      if (scriptRan) {
        ggLog('${path.basename(options.script!)} ran already.');
        return;
      }
      step = 'run ${path.basename(options.script!)}';
      ggLog('Running ${options.script} ...');
      await _script!(directory: dir, ggLog: ggLog);
    }

    try {
      final branch = await _git(dir, ['branch', '--show-current']);
      if (branch != options.branch) {
        throw Exception(
          'The checkout is on »$branch«, not on '
          '»${options.branch}«.',
        );
      }
      if (options.script != null) {
        scriptRan = (await changesOf(dir, base: base)).isNotEmpty;
      }
      step = 'install the dependencies';
      await _install(dir);

      for (final task in MaintainTask.values.where(options.tasks.contains)) {
        // The script runs before the DNA, which regenerates on top of it.
        if (task == MaintainTask.dna) await runScript();
        step = task.flag;
        ggLog('Running --${task.flag} ...');
        await _tasks[task]!(directory: dir, ggLog: ggLog);
      }
      if (!options.tasks.contains(MaintainTask.dna)) await runScript();

      step = 'detect the changes';
      final changes = await changesOf(dir, base: base);
      if (changes.isEmpty) return result(RepoOutcome.unchanged, '');
      final summary = summarize(changes);
      ggLog('Changed: $summary');
      if (options.dryRun) return result(RepoOutcome.changed, summary);

      step = 'commit';
      await _commit(directory: dir, ggLog: ggLog, message: options.message);
      step = 'merge';
      await _merge(
        directory: dir,
        ggLog: ggLog,
        message: options.message,
        resume: resume,
      );
      return result(RepoOutcome.merged, summary);
    } catch (e) {
      ggLog('Failed to $step: $e');
      return result(RepoOutcome.failed, '$e', step: step);
    }
  }

  // ...........................................................................
  /// Returns the files that changed in [dir] since the commit [base].
  ///
  /// Lock files and gg's state below `.gg/` do not count: they change on
  /// every run and nobody depending on the repo sees them.
  Future<List<String>> changesOf(Directory dir, {required String base}) async {
    final committed = await _git(dir, ['diff', '--name-only', base, 'HEAD']);
    // Not trimmed: the first status column may be a space.
    final status = await _shell.run('git', [
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], directory: dir);
    final uncommitted = status
        .split('\n')
        .where((line) => line.length > 3)
        .map((line) => line.substring(3).split(' -> ').last);
    final files =
        {...committed.split('\n'), ...uncommitted}
            .map((file) => file.trim().replaceAll('"', ''))
            .where((file) => file.isNotEmpty && !_isBookkeeping(file))
            .toList()
          ..sort();
    return files;
  }

  // ...........................................................................
  /// Shortens [files] to the manifests among them and the count of the rest.
  static String summarize(List<String> files) {
    const manifests = {'pubspec.yaml', 'package.json'};
    final shown = files.where(manifests.contains).toList();
    final others = files.length - shown.length;
    return [
      ...shown,
      if (others > 0) '$others ${others == 1 ? 'other file' : 'other files'}',
    ].join(', ');
  }

  // ...........................................................................
  final Shell _shell;
  final Map<MaintainTask, RepoTask> _tasks;
  final RepoTask? _script;
  final CommitStep _commit;
  final MergeStep _merge;

  static const _lockFiles = {
    'pubspec.lock',
    'pnpm-lock.yaml',
    'package-lock.json',
    'yarn.lock',
  };

  // ...........................................................................
  bool _isBookkeeping(String file) =>
      _lockFiles.contains(path.posix.basename(file)) || file.startsWith('.gg/');

  // ...........................................................................
  Future<String> _git(Directory dir, List<String> args) async =>
      (await _shell.run('git', args, directory: dir)).trim();

  // ...........................................................................
  Future<void> _install(Directory dir) async {
    if (File(path.join(dir.path, 'pubspec.yaml')).existsSync()) {
      final flutter = detectProjectType(dir) == ProjectType.flutter;
      await _shell.run(flutter ? 'flutter' : 'dart', [
        'pub',
        'get',
      ], directory: dir);
    }
    if (File(path.join(dir.path, 'package.json')).existsSync()) {
      final pm = detectTypeScriptPackageManager(dir);
      await _shell.run(pm.executable, [
        'install',
        // Audit and funding requests need the registry and can take long.
        if (pm == TypeScriptPackageManager.npm) ...['--no-audit', '--no-fund'],
      ], directory: dir);
    }
  }

  // ...........................................................................
  static Map<MaintainTask, RepoTask> _defaultTasks(
    MaintainOptions options,
    Shell shell,
  ) => {
    MaintainTask.sdk: UpgradeSdk(shell: shell).apply,
    MaintainTask.deps: UpgradeDeps(major: options.major).apply,
    MaintainTask.dna: UpgradeDna(shell: shell).apply,
  };

  // ...........................................................................
  // coverage:ignore-start
  static Future<void> _defaultCommit({
    required Directory directory,
    required GgLog ggLog,
    required String message,
  }) =>
      gg.DoCommit(ggLog: ggLog)
          .get(directory: directory, ggLog: ggLog, message: message);

  static Future<void> _defaultMerge({
    required Directory directory,
    required GgLog ggLog,
    required String message,
    required bool resume,
  }) => gg.DoPublish(ggLog: ggLog).get(
    directory: directory,
    ggLog: ggLog,
    message: message,
    mergeOnly: true,
    deleteFeatureBranch: true,
    askBeforePublishing: false,
    upgrade: false,
    resume: resume,
  );
  // coverage:ignore-end
}
