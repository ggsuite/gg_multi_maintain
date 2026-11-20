// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_publish/gg_publish.dart' show IsPublished;
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import '../tasks/upgrade_deps.dart';
import '../tasks/upgrade_dna.dart';
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
/// like `gg one do publish --merge-only`.
typedef MergeStep = Future<void> Function({
  required Directory directory,
  required GgLog ggLog,
  required String message,
});

/// Tells whether a package was ever published to its registries.
typedef IsPublishedStep = Future<bool> Function({
  required Directory directory,
  required GgLog ggLog,
});

// #############################################################################
/// Maintains one repo in a fresh clone of its own.
///
/// The ocean checkout is never touched. Each repo is cloned to
/// `<run>/<org>/<repo>` and maintained on the run's feature branch:
///
/// 1. clone, skip a package that was never published (its first version is
///    published by hand), create the branch, install the dependencies
/// 2. run the selected tasks: SDK, dependencies, DNA
/// 3. stop as unchanged when only lock files or gg's own state changed
/// 4. commit with `gg one do commit`, which runs all checks and tests
/// 5. merge into the main branch with `gg one do publish --merge-only`: no
///    version increase, no upload, no tag. The changes wait below
///    `## Unreleased` until a ticket releases the repo
///
/// A finished clone is deleted; a failed one is kept for a look.
class RepoMaintainer {
  /// Constructor
  RepoMaintainer({
    required this.options,
    required this.runDir,
    Shell shell = const Shell(),
    Map<MaintainTask, RepoTask>? tasks,
    IsPublishedStep? isPublished,
    CommitStep? commit,
    MergeStep? merge,
  }) : _shell = shell,
       _tasks = tasks ?? _defaultTasks(options, shell),
       _isPublished = isPublished ?? _defaultIsPublished,
       _commit = commit ?? _defaultCommit,
       _merge = merge ?? _defaultMerge;

  /// A maintainer whose steps only log.
  factory RepoMaintainer.example({
    MaintainOptions? options,
    Directory? runDir,
    Shell? shell,
    Map<MaintainTask, RepoTask>? tasks,
    IsPublishedStep? isPublished,
    CommitStep? commit,
    MergeStep? merge,
  }) => RepoMaintainer(
    options: options ?? MaintainOptions.example(),
    runDir: runDir ?? Directory.systemTemp,
    shell: shell ?? const Shell(),
    tasks:
        tasks ??
        {
          for (final task in MaintainTask.values)
            task: ({required directory, required ggLog}) async =>
                ggLog(task.flag),
        },
    isPublished:
        isPublished ?? ({required directory, required ggLog}) async => true,
    commit:
        commit ??
        ({required directory, required ggLog, required message}) async =>
            ggLog('commit'),
    merge:
        merge ??
        ({required directory, required ggLog, required message}) async =>
            ggLog('merge'),
  );

  // ...........................................................................
  /// What to do.
  final MaintainOptions options;

  /// The folder of this run, `<workspace>/.maintain/<run id>`.
  final Directory runDir;

  // ...........................................................................
  /// Maintains [repo] and reports how it ended.
  Future<RepoResult> maintain({
    required OceanRepo repo,
    required GgLog ggLog,
    String? logPath,
  }) async {
    final dir = cloneDirOf(repo);
    var step = 'clone';
    RepoResult result(RepoOutcome outcome, String detail) => RepoResult(
      repo: repo,
      outcome: outcome,
      detail: detail,
      logPath: logPath,
    );

    try {
      await _clone(repo, dir);
      step = 'check the registry';
      if (!await _isPublished(directory: dir, ggLog: ggLog)) {
        _delete(dir);
        return result(
          RepoOutcome.skipped,
          'never published, publish the first version by hand',
        );
      }

      step = 'create the branch';
      final base = await _git(dir, ['rev-parse', 'HEAD']);
      await _git(dir, ['checkout', '-b', options.branch]);
      step = 'install the dependencies';
      await _install(dir);

      for (final task in MaintainTask.values.where(options.tasks.contains)) {
        step = task.flag;
        ggLog('Running --${task.flag} ...');
        await _tasks[task]!(directory: dir, ggLog: ggLog);
      }

      step = 'detect the changes';
      final changes = await changesOf(dir, base: base);
      if (changes.isEmpty) {
        _delete(dir);
        return result(RepoOutcome.unchanged, '');
      }
      final summary = summarize(changes);
      ggLog('Changed: $summary');
      if (options.dryRun) {
        _delete(dir);
        return result(RepoOutcome.changed, summary);
      }

      step = 'commit';
      await _commit(directory: dir, ggLog: ggLog, message: options.message);
      step = 'merge';
      await _merge(directory: dir, ggLog: ggLog, message: options.message);
      _delete(dir);
      return result(RepoOutcome.merged, summary);
    } catch (e) {
      ggLog('Failed to $step: $e');
      return RepoResult(
        repo: repo,
        outcome: RepoOutcome.failed,
        detail: '$e',
        step: step,
        clonePath: dir.path,
        logPath: logPath,
      );
    }
  }

  // ...........................................................................
  /// The folder [repo] is cloned to.
  Directory cloneDirOf(OceanRepo repo) =>
      Directory(path.join(runDir.path, repo.org, repo.name));

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
  final IsPublishedStep _isPublished;
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
  Future<void> _clone(OceanRepo repo, Directory dir) async {
    final parent = dir.parent..createSync(recursive: true);
    await _shell.run('git', [
      'clone',
      '--quiet',
      repo.url,
      path.basename(dir.path),
    ], directory: parent);
  }

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
  void _delete(Directory dir) {
    try {
      dir.deleteSync(recursive: true);
      // coverage:ignore-start
    } on FileSystemException {
      // Windows keeps files open for a moment; the run folder stays then.
    }
    // coverage:ignore-end
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
  static Future<bool> _defaultIsPublished({
    required Directory directory,
    required GgLog ggLog,
  }) => IsPublished(ggLog: ggLog).get(directory: directory, ggLog: ggLog);

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
  }) => gg.DoPublish(ggLog: ggLog).get(
    directory: directory,
    ggLog: ggLog,
    message: message,
    mergeOnly: true,
    deleteFeatureBranch: true,
    askBeforePublishing: false,
    upgrade: false,
  );
  // coverage:ignore-end
}
