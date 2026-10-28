// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'ocean_repo.dart';

// #############################################################################
/// How maintaining a repo ended.
enum RepoOutcome {
  /// Changed, committed and published.
  published('Published'),

  /// Changed, but not committed because of `--dry-run`.
  changed('Would change'),

  /// Nothing to upgrade.
  unchanged('Unchanged'),

  /// Left out on purpose.
  skipped('Skipped'),

  /// Not started because a repo it depends on did not succeed.
  blocked('Blocked'),

  /// A step failed; the clone is kept for a look.
  failed('Failed');

  const RepoOutcome(this.title);

  /// The heading of the outcome in the summary.
  final String title;

  /// Whether the repos depending on this one may continue.
  bool get letsDependentsRun => this != failed && this != blocked;
}

// #############################################################################
/// The result of maintaining one repo.
class RepoResult {
  /// Constructor
  const RepoResult({
    required this.repo,
    required this.outcome,
    this.detail = '',
    this.step,
    this.clonePath,
    this.logPath,
  });

  /// A published repo.
  factory RepoResult.example({
    OceanRepo? repo,
    RepoOutcome? outcome,
    String? detail,
    String? step,
    String? clonePath,
    String? logPath,
  }) => RepoResult(
    repo: repo ?? OceanRepo.example(),
    outcome: outcome ?? RepoOutcome.published,
    detail: detail ?? '1.2.4',
    step: step,
    clonePath: clonePath,
    logPath: logPath,
  );

  // ...........................................................................
  /// The repo.
  final OceanRepo repo;

  /// How it ended.
  final RepoOutcome outcome;

  /// The published version, the changed files, the reason or the error.
  final String detail;

  /// The step that failed.
  final String? step;

  /// The kept clone of a failed repo.
  final String? clonePath;

  /// The full log of the repo.
  final String? logPath;
}
