// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

// #############################################################################
/// A repo of the ocean that `gg do maintain` works on.
class OceanRepo {
  /// Constructor
  const OceanRepo({
    required this.org,
    required this.name,
    required this.directory,
    required this.url,
  });

  /// A repo of ggsuite.
  factory OceanRepo.example({
    String? org,
    String? name,
    Directory? directory,
    String? url,
  }) {
    final repoName = name ?? 'gg_json';
    final repoOrg = org ?? 'ggsuite';
    return OceanRepo(
      org: repoOrg,
      name: repoName,
      directory: directory ?? Directory('.ocean/$repoOrg/$repoName'),
      url: url ?? 'https://github.com/$repoOrg/$repoName.git',
    );
  }

  // ...........................................................................
  /// The organization folder the repo lives in.
  final String org;

  /// The folder name of the repo.
  final String name;

  /// The ocean checkout; only read, never changed.
  final Directory directory;

  /// The remote the fresh clone is made from.
  final String url;

  /// Identifies the repo across organizations, e.g. `ggsuite/gg_json`.
  String get key => '$org/$name';

  @override
  String toString() => key;
}
