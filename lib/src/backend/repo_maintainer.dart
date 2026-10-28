// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_publish/gg_publish.dart' show IsPublished;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../maintain_options.dart';
import '../tasks/upgrade_deps.dart';
import '../tasks/upgrade_dna.dart';
import '../tasks/upgrade_sdk.dart';
import '../tasks/version_increment.dart';
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

/// Publishes the committed checkout, like `gg one do publish`.
typedef PublishStep = Future<void> Function({
  required Directory directory,
  required GgLog ggLog,
  required String message,
  required String versionIncrement,
  required bool pana,
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
/// 5. publish with `gg one do publish`, which merges and waits for the
///    registry, so the repos depending on this one see the new version
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
    PublishStep? publish,
    this._versionIncrement = const VersionIncrement(),
    Future<Set<PublishTarget>> Function(Directory directory)? publishTargets,
  }) : _shell = shell,
       _tasks = tasks ?? _defaultTasks(options, shell),
       _isPublished = isPublished ?? _defaultIsPublished,
       _commit = commit ?? _defaultCommit,
       _publish = publish ?? _defaultPublish,
       _publishTargets = publishTargets ?? publishTargetsOf;

  /// A maintainer whose steps only log.
  factory RepoMaintainer.example({
    MaintainOptions? options,
    Directory? runDir,
    Shell? shell,
    Map<MaintainTask, RepoTask>? tasks,
    IsPublishedStep? isPublished,
    CommitStep? commit,
    PublishStep? publish,
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
    publish:
        publish ??
        ({
          required directory,
          required ggLog,
          required message,
          required versionIncrement,
          required pana,
        }) async => ggLog('publish $versionIncrement'),
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

      final before = VersionIncrement.read(dir);
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

      final increment =
          options.versionIncrement ??
          _versionIncrement.derive(
            before: before,
            after: VersionIncrement.read(dir),
          );

      step = 'commit';
      await _commit(directory: dir, ggLog: ggLog, message: options.message);
      step = 'publish';
      await _serialIfNpm(
        dir,
        () => _publish(
          directory: dir,
          ggLog: ggLog,
          message: options.message,
          versionIncrement: increment,
          pana: options.pana,
        ),
      );
      final version = versionOf(dir);
      _delete(dir);
      return result(RepoOutcome.published, version);
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
  /// Returns the version the manifest of [dir] carries.
  static String versionOf(Directory dir) {
    final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
      return '${yaml['version'] ?? ''}';
    }
    final packageJson = File(path.join(dir.path, 'package.json'));
    final match = RegExp(r'"version"\s*:\s*"([^"]*)"')
        .firstMatch(packageJson.readAsStringSync());
    return match?.group(1) ?? '';
  }

  // ...........................................................................
  final Shell _shell;
  final Map<MaintainTask, RepoTask> _tasks;
  final IsPublishedStep _isPublished;
  final CommitStep _commit;
  final PublishStep _publish;
  final VersionIncrement _versionIncrement;
  final Future<Set<PublishTarget>> Function(Directory directory)
  _publishTargets;

  /// npm publishes share the terminal for one-time passwords: one at a time.
  Future<void> _npmQueue = Future.value();

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
      final pm = detectTypeScriptPackageManager(dir).executable;
      await _shell.run(pm, ['install'], directory: dir);
    }
  }

  // ...........................................................................
  Future<void> _serialIfNpm(Directory dir, Future<void> Function() run) async {
    if (!(await _publishTargets(dir)).contains(PublishTarget.npm)) {
      return run();
    }
    final previous = _npmQueue;
    final done = Completer<void>();
    _npmQueue = done.future;
    await previous;
    try {
      await run();
    } finally {
      done.complete();
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

  static Future<void> _defaultPublish({
    required Directory directory,
    required GgLog ggLog,
    required String message,
    required String versionIncrement,
    required bool pana,
  }) => gg.DoPublish(ggLog: ggLog).get(
    directory: directory,
    ggLog: ggLog,
    message: message,
    versionIncrement: versionIncrement,
    deleteFeatureBranch: true,
    askBeforePublishing: false,
    upgrade: false,
    pana: pana,
  );
  // coverage:ignore-end
}
