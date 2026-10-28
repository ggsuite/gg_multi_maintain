// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_multi_core/gg_multi_core.dart';
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import 'ocean_repo.dart';

// #############################################################################
/// The repos of one run and the ones left out on purpose.
typedef RepoSelectionResult = ({
  List<OceanRepo> selected,
  Map<OceanRepo, String> skipped,
});

// #############################################################################
/// Picks the ocean repos `gg do maintain` works on.
///
/// Repos outside `--org` and `--repo` are dropped silently. Test projects,
/// repos without a remote and repos that publish to no registry are reported
/// as skipped, because maintaining them would publish nothing.
class RepoSelection {
  /// Constructor
  const RepoSelection({
    Future<Set<PublishTarget>> Function(Directory directory)? publishTargets,
  }) : _publishTargets = publishTargets ?? publishTargetsOf;

  /// A selection that asks the real manifests.
  factory RepoSelection.example() => const RepoSelection();

  // ...........................................................................
  /// Returns the repos of [oceanPath] that [options] selects.
  Future<RepoSelectionResult> select({
    required String oceanPath,
    required MaintainOptions options,
  }) async {
    final selected = <OceanRepo>[];
    final skipped = <OceanRepo, String>{};
    for (final dir in RepoFolderResolver.repoDirs(oceanPath)) {
      final repo = _repoOf(dir, oceanPath);
      if (!_matches(repo, options)) continue;
      final reason = await _skipReason(repo);
      if (reason == null) {
        selected.add(repo);
      } else {
        skipped[repo] = reason;
      }
    }
    return (selected: selected, skipped: skipped);
  }

  // ...........................................................................
  final Future<Set<PublishTarget>> Function(Directory directory)
  _publishTargets;

  // ...........................................................................
  OceanRepo _repoOf(Directory dir, String oceanPath) {
    final parent = path.dirname(dir.path);
    final url = RepoFolderResolver.remoteUrl(dir) ?? '';
    final org = path.equals(parent, oceanPath)
        ? RepoFolderResolver.organizationOf(url) ?? ''
        : path.basename(parent);
    return OceanRepo(
      org: org,
      name: path.basename(dir.path),
      directory: dir,
      url: url,
    );
  }

  // ...........................................................................
  bool _matches(OceanRepo repo, MaintainOptions options) {
    if (options.orgs.isNotEmpty && !options.orgs.contains(repo.org)) {
      return false;
    }
    if (options.repos.isEmpty) return true;
    return options.repos.any(
      (pattern) =>
          _glob(pattern).hasMatch(repo.name) ||
          _glob(pattern).hasMatch(repo.key),
    );
  }

  // ...........................................................................
  RegExp _glob(String pattern) =>
      RegExp('^${pattern.split('*').map(RegExp.escape).join('.*')}\$');

  // ...........................................................................
  Future<String?> _skipReason(OceanRepo repo) async {
    if (repo.name.startsWith(RegExp('testproject[_-]'))) {
      return 'a test project';
    }
    if (repo.url.isEmpty) return 'no remote';
    if ((await _publishTargets(repo.directory)).isEmpty) {
      return 'publishes to no registry';
    }
    return null;
  }
}
