// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_one/gg_one.dart' show publishStateFile;
import 'package:path/path.dart' as path;

import '../maintain_options.dart';
import 'ocean_repo.dart';
import 'repo_result.dart';

// #############################################################################
/// What `gg do maintain --continue` needs to go on with a run.
///
/// Kept below the key `maintain` of `<ticket>/.gg/publish_state.json`, the
/// file that holds the run state of every ticket; the other keys of the file
/// stay as they are. Saved after every repo, so even a run that was killed
/// can be continued.
class MaintainState {
  /// Constructor
  MaintainState({
    required this.options,
    required this.repos,
    Map<String, Set<String>>? dependencies,
    Map<String, String>? bases,
    Map<String, RepoResult>? results,
  }) : dependencies = dependencies ?? {},
       bases = bases ?? {},
       results = results ?? {};

  /// The state of a run over one repo.
  factory MaintainState.example() => MaintainState(
    options: MaintainOptions.example(),
    repos: [OceanRepo.example()],
  );

  // ...........................................................................
  /// The options the run was started with.
  final MaintainOptions options;

  /// The repos of the run, skipped ones included, with their ocean checkout.
  final List<OceanRepo> repos;

  /// The keys of the repos of the run each repo depends on, by repo key.
  final Map<String, Set<String>> dependencies;

  /// The commit each repo was at before the run, by repo key.
  final Map<String, String> bases;

  /// How the repos ended so far, by repo key.
  final Map<String, RepoResult> results;

  // ...........................................................................
  /// Whether [repo] needs no further work.
  bool isDone(OceanRepo repo) => results[repo.key]?.outcome.isDone ?? false;

  /// The repos that still need work.
  List<OceanRepo> get todo => repos.where((repo) => !isDone(repo)).toList();

  // ...........................................................................
  /// The file of the ticket in [folder].
  static File fileIn(Directory folder) => publishStateFile(folder);

  /// Whether [folder] holds the state of a run.
  static bool existsIn(Directory folder) => fileIn(folder).existsSync();

  /// The key of the state in the file.
  static const key = 'maintain';

  // ...........................................................................
  /// Writes the state into [folder], keeping the other keys of the file.
  void save(Directory folder) {
    final file = fileIn(folder);
    final json = _read(file) ?? <String, dynamic>{};
    json[key] = _toJson(folder);
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}'
        '\n',
      );
  }

  // ...........................................................................
  /// Reads the state of the run in [folder]; null when it has none.
  static MaintainState? load(Directory folder) {
    final json = _read(fileIn(folder))?[key];
    if (json is! Map<String, dynamic>) return null;
    final repos = [
      for (final repo in (json['repos'] as List).cast<Map<String, dynamic>>())
        OceanRepo(
          org: repo['org'] as String,
          name: repo['name'] as String,
          url: repo['url'] as String,
          directory: Directory(
            path.join(folder.path, repo['directory'] as String),
          ),
        ),
    ];
    final byKey = {for (final repo in repos) repo.key: repo};
    final results = (json['results'] as Map<String, dynamic>? ?? {}).map((
      repoKey,
      value,
    ) {
      final result = value as Map<String, dynamic>;
      return MapEntry(
        repoKey,
        RepoResult(
          repo: byKey[repoKey]!,
          outcome: RepoOutcome.values.byName(result['outcome'] as String),
          detail: result['detail'] as String? ?? '',
          step: result['step'] as String?,
        ),
      );
    });
    return MaintainState(
      options: MaintainOptions.fromJson(
        json['options'] as Map<String, dynamic>,
      ),
      repos: repos,
      dependencies: (json['dependencies'] as Map<String, dynamic>? ?? {}).map(
        (repoKey, value) =>
            MapEntry(repoKey, (value as List).cast<String>().toSet()),
      ),
      bases: (json['bases'] as Map<String, dynamic>? ?? {})
          .cast<String, String>(),
      results: results,
    );
  }

  // ...........................................................................
  Map<String, dynamic> _toJson(Directory folder) => {
    'options': options.toJson(),
    'repos': [
      for (final repo in repos)
        {
          'org': repo.org,
          'name': repo.name,
          'url': repo.url,
          'directory': path.relative(repo.directory.path, from: folder.path),
        },
    ],
    'dependencies': {
      for (final MapEntry(key: repoKey, value: keys) in dependencies.entries)
        repoKey: keys.toList()..sort(),
    },
    'bases': bases,
    'results': {
      for (final MapEntry(key: repoKey, value: result) in results.entries)
        repoKey: {
          'outcome': result.outcome.name,
          if (result.detail.isNotEmpty) 'detail': result.detail,
          if (result.step != null) 'step': result.step,
        },
    },
  };

  // ...........................................................................
  static Map<String, dynamic>? _read(File file) {
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    return json is Map<String, dynamic> ? json : null;
  }
}
