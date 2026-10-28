// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_console_colors/gg_console_colors.dart';

import 'repo_result.dart';

// #############################################################################
/// Summarizes a run of `gg do maintain`, grouped by outcome.
class MaintainReport {
  /// Constructor
  const MaintainReport({required this.results});

  /// A report of one published repo.
  factory MaintainReport.example({List<RepoResult>? results}) =>
      MaintainReport(results: results ?? [RepoResult.example()]);

  // ...........................................................................
  /// The results of all repos, in any order.
  final List<RepoResult> results;

  // ...........................................................................
  /// Whether a repo failed or was blocked.
  bool get hasProblems =>
      results.any((result) => !result.outcome.letsDependentsRun);

  // ...........................................................................
  /// Returns the lines of the summary.
  List<String> lines() {
    final lines = <String>[];
    for (final outcome in RepoOutcome.values) {
      final group =
          results.where((result) => result.outcome == outcome).toList()
            ..sort((a, b) => a.repo.key.compareTo(b.repo.key));
      if (group.isEmpty) continue;
      lines.add(_color(outcome)('${outcome.title} (${group.length}):'));
      for (final result in group) {
        lines.addAll(_linesOf(result));
      }
    }
    return lines;
  }

  // ...........................................................................
  List<String> _linesOf(RepoResult result) {
    final head = result.detail.isEmpty
        ? '  ${result.repo.key}'
        : '  ${result.repo.key}: ${_firstLine(result)}';
    return [
      head,
      if (result.clonePath != null) '    clone: ${result.clonePath}',
      if (result.outcome == RepoOutcome.failed && result.logPath != null)
        '    log:   ${result.logPath}',
    ];
  }

  // ...........................................................................
  String _firstLine(RepoResult result) {
    final first = result.detail.trim().split('\n').first;
    return result.step == null ? first : '${result.step}: $first';
  }

  // ...........................................................................
  String Function(Object) _color(RepoOutcome outcome) => switch (outcome) {
    RepoOutcome.published => green,
    RepoOutcome.changed => blue,
    RepoOutcome.unchanged || RepoOutcome.skipped => darkGray,
    RepoOutcome.blocked => yellow,
    RepoOutcome.failed => red,
  };
}
