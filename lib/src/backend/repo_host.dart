// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:gg_multi_workspace/gg_multi_workspace.dart';
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import 'ocean_repo.dart';
import 'shell.dart';

// #############################################################################
/// Provides the checkouts a run of `gg do maintain` works in.
///
/// A run [create]s one folder and [add]s a checkout of every selected repo
/// on the run's branch to it. It [close]s the folder again when everything
/// went well. A run with problems keeps the folder: the developer fixes it
/// there and continues.
abstract class RepoHost {
  /// Constructor
  const RepoHost({this.shell = const Shell()});

  /// Runs git.
  final Shell shell;

  // ...........................................................................
  /// Prepares the workspace at [workspacePath] before a new run.
  Future<void> prepare({required String workspacePath, required GgLog ggLog});

  /// The folder of the run [options] describes.
  Directory folderOf({
    required String workspacePath,
    required MaintainOptions options,
  });

  /// Creates the empty [folder] of the run.
  Future<void> create({
    required Directory folder,
    required MaintainOptions options,
    required GgLog ggLog,
  });

  /// Adds a checkout of every repo in [repos] of [oceanPath] to [folder].
  Future<void> add({
    required Directory folder,
    required String oceanPath,
    required MaintainOptions options,
    required List<OceanRepo> repos,
    required GgLog ggLog,
  });

  /// Removes the folder of a run that went well.
  Future<void> close({required Directory folder, required GgLog ggLog});

  // ...........................................................................
  /// The checkouts of [repos] in [folder] by repo key, found by their
  /// remote in one pass over [folder]; a repo without checkout is missing.
  Map<String, Directory> checkoutsOf(
    Directory folder,
    Iterable<OceanRepo> repos,
  ) {
    if (!folder.existsSync()) return {};
    final byRemote = <String, Directory>{};
    for (final dir in RepoFolderResolver.repoDirs(folder.path)) {
      final url = RepoFolderResolver.remoteUrl(dir);
      if (url == null) continue;
      // A url gg cannot attribute, like a local path, is compared as it is.
      byRemote.putIfAbsent(
        RepoFolderResolver.urlIdentity(url) ?? url,
        () => dir,
      );
    }
    return {
      for (final repo in repos)
        repo.key:
            ?byRemote[RepoFolderResolver.urlIdentity(repo.url) ?? repo.url],
    };
  }

  /// The checkout of [repo] in [folder]; null when [folder] holds none.
  Directory? checkoutOf(Directory folder, OceanRepo repo) =>
      checkoutsOf(folder, [repo])[repo.key];

  // ...........................................................................
  /// Sets the checkouts of [repos] in [folder] back to their last commit.
  Future<void> restore(Directory folder, List<OceanRepo> repos) async {
    for (final dir in checkoutsOf(folder, repos).values) {
      await shell.run('git', ['reset', '--quiet', '--hard'], directory: dir);
      await shell.run('git', ['clean', '-fdq'], directory: dir);
    }
  }
}

// #############################################################################
/// Works in a normal ticket of the workspace.
///
/// [prepare] runs `gg do upgrade ocean`, [create] creates the ticket
/// `maintain_<run id>`, [add] adds the repos without localizing their
/// references, [close] moves the ticket to the trash with `gg do rm ticket`.
class TicketRepoHost extends RepoHost {
  /// Constructor
  const TicketRepoHost({super.shell});

  // ...........................................................................
  @override
  Directory folderOf({
    required String workspacePath,
    required MaintainOptions options,
  }) => Directory(path.join(workspacePath, options.branch));

  // ...........................................................................
  // coverage:ignore-start
  @override
  Future<void> prepare({required String workspacePath, required GgLog ggLog}) =>
      _run(UpdateOceanCommand(ggLog: ggLog, rootPath: workspacePath), []);

  // ...........................................................................
  @override
  Future<void> create({
    required Directory folder,
    required MaintainOptions options,
    required GgLog ggLog,
  }) => _run(TicketCommand(ggLog: ggLog, rootPath: folder.parent.path), [
    path.basename(folder.path),
    '--message',
    '${options.message} in all repos',
  ]);

  // ...........................................................................
  @override
  Future<void> add({
    required Directory folder,
    required String oceanPath,
    required MaintainOptions options,
    required List<OceanRepo> repos,
    required GgLog ggLog,
  }) async {
    try {
      await _run(
        AddCommand(
          ggLog: ggLog,
          oceanWorkspacePath: oceanPath,
          executionPath: folder.path,
        ),
        [
          '--no-localize',
          '--no-transitive',
          for (final repo in repos) repo.key,
        ],
      );
    } finally {
      // Without localizing, `do add` leaves the files it maintains — like
      // .gitattributes — uncommitted. They are no maintenance of the repo.
      await restore(folder, repos);
    }
  }

  // ...........................................................................
  @override
  Future<void> close({required Directory folder, required GgLog ggLog}) =>
      // The merge already deleted the feature branches.
      _run(RemoveTicketCommand(ggLog: ggLog, rootPath: folder.parent.path), [
        path.basename(folder.path),
        '--no-delete-remote-branch',
      ]);

  // ...........................................................................
  static Future<void> _run(Command<dynamic> command, List<String> args) =>
      (CommandRunner<dynamic>(
        'gg',
        '',
      )..addCommand(command)).run([command.name, ...args]);
  // coverage:ignore-end
}

// #############################################################################
/// Clones the repos into a folder of their own, for `--dry-run` and tests.
///
/// Nothing in the workspace changes: the ocean is not synced, no ticket is
/// created. Every clone sits below its organization.
class CloneRepoHost extends RepoHost {
  /// Constructor
  CloneRepoHost({super.shell, Directory? root})
    : root = root ?? Directory.systemTemp;

  /// A host cloning into the system temp folder.
  factory CloneRepoHost.example({Directory? root}) => CloneRepoHost(root: root);

  /// The folder the run folders are created in.
  final Directory root;

  // ...........................................................................
  @override
  Future<void> prepare({
    required String workspacePath,
    required GgLog ggLog,
  }) async {}

  // ...........................................................................
  @override
  Directory folderOf({
    required String workspacePath,
    required MaintainOptions options,
  }) => Directory(path.join(root.path, 'gg_maintain_${options.runId}'));

  // ...........................................................................
  @override
  Future<void> create({
    required Directory folder,
    required MaintainOptions options,
    required GgLog ggLog,
  }) async => folder.createSync(recursive: true);

  // ...........................................................................
  @override
  Future<void> add({
    required Directory folder,
    required String oceanPath,
    required MaintainOptions options,
    required List<OceanRepo> repos,
    required GgLog ggLog,
  }) async {
    for (var i = 0; i < repos.length; i += options.jobs) {
      final batch = repos.skip(i).take(options.jobs);
      await Future.wait(
        batch.map((repo) => _clone(folder, repo, options, ggLog)),
      );
    }
  }

  // ...........................................................................
  /// Clones [repo]; a clone that fails leaves no checkout, the repo then
  /// fails alone.
  Future<void> _clone(
    Directory folder,
    OceanRepo repo,
    MaintainOptions options,
    GgLog ggLog,
  ) async {
    final dir = Directory(path.join(folder.path, repo.org, repo.name));
    try {
      dir.parent.createSync(recursive: true);
      await shell.run('git', [
        'clone',
        '--quiet',
        repo.url,
        repo.name,
      ], directory: dir.parent);
      await shell.run('git', [
        'checkout',
        '--quiet',
        '-b',
        options.branch,
      ], directory: dir);
    } on Exception catch (e) {
      ggLog('Could not clone ${repo.key}: $e');
    }
  }

  // ...........................................................................
  @override
  Future<void> close({required Directory folder, required GgLog ggLog}) async {
    try {
      folder.deleteSync(recursive: true);
      // coverage:ignore-start
    } on FileSystemException {
      // Windows keeps files open for a moment; the temp folder stays then.
    }
    // coverage:ignore-end
  }
}
