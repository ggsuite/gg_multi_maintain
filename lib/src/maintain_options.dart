// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:path/path.dart' as path;

// #############################################################################
/// A maintenance task `gg do maintain` can run in every repo.
enum MaintainTask {
  /// Raises the SDK constraint to the installed Dart or Node version.
  sdk('upgrade-sdk', 'the SDK'),

  /// Raises the dependencies to their newest versions.
  deps('upgrade-deps', 'the dependencies'),

  /// Raises the DNA layers to their newest versions and regenerates the DNA.
  dna('upgrade-dna', 'the DNA');

  const MaintainTask(this.flag, this.subject);

  /// The command line flag that selects the task.
  final String flag;

  /// The words the commit and merge message use for the task.
  final String subject;
}

// #############################################################################
/// What `gg do maintain` does and where.
class MaintainOptions {
  /// Constructor
  const MaintainOptions({
    required this.tasks,
    required this.runId,
    this.major = false,
    this.jobs = 4,
    this.dryRun = false,
    this.orgs = const [],
    this.repos = const [],
    this.script,
  });

  /// Options that upgrade everything in a fixed run.
  factory MaintainOptions.example({
    Set<MaintainTask>? tasks,
    String? runId,
    bool? major,
    int? jobs,
    bool? dryRun,
    List<String>? orgs,
    List<String>? repos,
    String? script,
  }) => MaintainOptions(
    tasks: tasks ?? MaintainTask.values.toSet(),
    runId: runId ?? '2026_10_28_074200',
    major: major ?? false,
    jobs: jobs ?? 2,
    dryRun: dryRun ?? false,
    orgs: orgs ?? const [],
    repos: repos ?? const [],
    script: script,
  );

  /// Reads options [toJson] wrote.
  factory MaintainOptions.fromJson(Map<String, dynamic> json) =>
      MaintainOptions(
        runId: json['runId'] as String,
        tasks: {
          for (final flag in (json['tasks'] as List).cast<String>())
            MaintainTask.values.firstWhere((task) => task.flag == flag),
        },
        major: json['major'] as bool,
        jobs: json['jobs'] as int,
        orgs: (json['orgs'] as List).cast<String>(),
        repos: (json['repos'] as List).cast<String>(),
        script: json['script'] as String?,
      );

  // ...........................................................................
  /// The tasks to run; at least one, or a [script].
  final Set<MaintainTask> tasks;

  /// Identifies the run: names the ticket and the feature branch.
  final String runId;

  /// Allows major version jumps when upgrading the dependencies.
  final bool major;

  /// How many repos are maintained at the same time.
  final int jobs;

  /// Applies the tasks in temporary clones, but neither commits nor merges.
  final bool dryRun;

  /// Limits the run to these organizations; empty means all.
  final List<String> orgs;

  /// Limits the run to repos matching these patterns; `*` is a wildcard.
  final List<String> repos;

  /// The absolute path of a script every repo runs, or null. It runs after
  /// the SDK and the dependencies, before the DNA: the DNA then regenerates
  /// on top of what the script changed.
  final String? script;

  // ...........................................................................
  /// The ticket of the run; also the feature branch of every repo.
  String get branch => 'maintain_$runId';

  /// Returns the options as JSON, for `--continue`.
  Map<String, dynamic> toJson() => {
    'runId': runId,
    'tasks': [
      for (final task in MaintainTask.values)
        if (tasks.contains(task)) task.flag,
    ],
    'major': major,
    'jobs': jobs,
    'orgs': orgs,
    'repos': repos,
    'script': ?script,
  };

  /// The commit and merge message, e.g. »Upgrade the SDK and the DNA« or
  /// »Upgrade the DNA and run migrate.dart«.
  String get message {
    final subjects = MaintainTask.values
        .where(tasks.contains)
        .map((task) => task.subject)
        .toList();
    final run = script == null ? null : 'run ${path.basename(script!)}';
    if (subjects.isEmpty) return 'Run ${path.basename(script!)}';
    final last = subjects.removeLast();
    final head = subjects.join(', ');
    final upgrade = 'Upgrade ${head.isEmpty ? last : '$head and $last'}';
    return run == null ? upgrade : '$upgrade and $run';
  }

  /// Returns a run id for [time], e.g. `2026_10_28_074200`.
  static String runIdOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}_${two(time.month)}_${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
