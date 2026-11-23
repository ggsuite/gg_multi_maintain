// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'ocean_repo.dart';

// #############################################################################
/// How maintaining a repo ended.
enum RepoOutcome {
  /// Changed, committed and merged into the main branch, not released.
  merged('Merged'),

  /// Changed, but not committed because of `--dry-run`.
  changed('Would change'),

  /// Nothing to upgrade.
  unchanged('Unchanged'),

  /// Left out on purpose.
  skipped('Skipped'),

  /// Not started because a repo it depends on did not succeed.
  blocked('Blocked'),

  /// A step failed; the checkout is kept to fix it.
  failed('Failed');

  const RepoOutcome(this.title);

  /// The heading of the outcome in the summary.
  final String title;

  /// Whether the repos depending on this one may continue.
  bool get letsDependentsRun => this != failed && this != blocked;

  /// Whether the repo needs no further work in a continued run.
  bool get isDone => this == merged || this == unchanged || this == skipped;
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
    this.checkoutPath,
    this.logPath,
  });

  /// A merged repo.
  factory RepoResult.example({
    OceanRepo? repo,
    RepoOutcome? outcome,
    String? detail,
    String? step,
    String? checkoutPath,
    String? logPath,
  }) => RepoResult(
    repo: repo ?? OceanRepo.example(),
    outcome: outcome ?? RepoOutcome.merged,
    detail: detail ?? 'pubspec.yaml',
    step: step,
    checkoutPath: checkoutPath,
    logPath: logPath,
  );

  // ...........................................................................
  /// The repo.
  final OceanRepo repo;

  /// How it ended.
  final RepoOutcome outcome;

  /// The changed files, the reason or the error.
  final String detail;

  /// The step that failed.
  final String? step;

  /// The checkout of a failed repo, to fix it there.
  final String? checkoutPath;

  /// The full log of the repo.
  final String? logPath;
}
