// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'ocean_repo.dart';

// #############################################################################
/// Tells which of the selected repos each repo waits for.
///
/// Dev dependencies count as well: a repo upgrading its DNA needs the DNA
/// layers published first. Cycles that close over a dev dependency are cut
/// by the graph, so the result is acyclic.
class DependencyOrder {
  /// Constructor
  DependencyOrder({Graph? graph}) : _graph = graph ?? Graph(ggLog: (_) {});

  /// An order built from the real manifests.
  factory DependencyOrder.example() => DependencyOrder();

  // ...........................................................................
  /// Maps the key of every repo in [repos] to the keys it depends on.
  ///
  /// The keys come in dependency order, so repos without dependencies start
  /// first.
  Future<Map<String, Set<String>>> get({
    required List<OceanRepo> repos,
    GgLog? ggLog,
  }) async {
    final roots = await _graph.get(
      directory: Directory.current,
      ggLog: ggLog ?? (_) {},
      packageDirs: repos.map((repo) => repo.directory).toList(),
    );
    final keyOf = {
      for (final repo in repos)
        path.canonicalize(repo.directory.path): repo.key,
    };
    final result = <String, Set<String>>{};
    void visit(Node node) {
      final key = keyOf[path.canonicalize(node.directory.path)]!;
      if (result.containsKey(key)) return;
      node.dependencies.values.forEach(visit);
      result[key] = {
        for (final dependency in node.dependencies.values)
          keyOf[path.canonicalize(dependency.directory.path)]!,
      };
    }

    roots.values.forEach(visit);

    // The graph keeps one folder per package name; the others still run.
    for (final repo in repos) {
      result.putIfAbsent(repo.key, () => {});
    }
    return result;
  }

  // ...........................................................................
  final Graph _graph;
}
