// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

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
    this.versionIncrement,
    this.pana = true,
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
    String? versionIncrement,
    bool? pana,
  }) => MaintainOptions(
    tasks: tasks ?? MaintainTask.values.toSet(),
    runId: runId ?? '2026_10_28_074200',
    major: major ?? false,
    jobs: jobs ?? 2,
    dryRun: dryRun ?? false,
    orgs: orgs ?? const [],
    repos: repos ?? const [],
    versionIncrement: versionIncrement,
    pana: pana ?? true,
  );

  // ...........................................................................
  /// The tasks to run, at least one.
  final Set<MaintainTask> tasks;

  /// Identifies the run: names the run folder and the feature branch.
  final String runId;

  /// Allows major version jumps when upgrading the dependencies.
  final bool major;

  /// How many repos are maintained at the same time.
  final int jobs;

  /// Applies the tasks, but neither commits nor publishes.
  final bool dryRun;

  /// Limits the run to these organizations; empty means all.
  final List<String> orgs;

  /// Limits the run to repos matching these patterns; `*` is a wildcard.
  final List<String> repos;

  /// patch, minor or major; null derives it from the changes.
  final String? versionIncrement;

  /// Runs pana before publishing Dart packages.
  final bool pana;

  // ...........................................................................
  /// The feature branch every repo is maintained on.
  String get branch => 'maintain_$runId';

  /// The commit and merge message, e.g. »Upgrade the SDK and the DNA«.
  String get message {
    final subjects = MaintainTask.values
        .where(tasks.contains)
        .map((task) => task.subject)
        .toList();
    final last = subjects.removeLast();
    final head = subjects.join(', ');
    return 'Upgrade ${head.isEmpty ? last : '$head and $last'}';
  }

  /// Returns a run id for [time], e.g. `2026_10_28_074200`.
  static String runIdOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}_${two(time.month)}_${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
