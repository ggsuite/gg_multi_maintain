// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

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
/// Repos outside `--org` and `--repo` are dropped silently. Repos without a
/// remote are reported as skipped: there is no main branch to merge into.
/// Test projects and private packages are maintained like every other repo,
/// maintenance releases nothing.
class RepoSelection {
  /// Constructor
  const RepoSelection();

  /// A selection by organization and name.
  factory RepoSelection.example() => const RepoSelection();

  // ...........................................................................
  /// Returns the repos of [oceanPath] that [options] selects.
  RepoSelectionResult select({
    required String oceanPath,
    required MaintainOptions options,
  }) {
    final selected = <OceanRepo>[];
    final skipped = <OceanRepo, String>{};
    for (final dir in RepoFolderResolver.repoDirs(oceanPath)) {
      final repo = _repoOf(dir, oceanPath);
      if (!_matches(repo, options)) continue;
      if (repo.url.isEmpty) {
        skipped[repo] = 'no remote';
      } else {
        selected.add(repo);
      }
    }
    return (selected: selected, skipped: skipped);
  }

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
}
