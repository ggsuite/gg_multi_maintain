// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;

// #############################################################################
/// Raises the dependencies of a repo, like `gg one do upgrade deps`.
///
/// Without [major] the constraints are only tightened to the newest
/// compatible versions; with it they may jump across major versions.
class UpgradeDeps {
  /// Constructor
  UpgradeDeps({required this.major, this._doUpgradeDeps});

  /// Upgrades without major jumps.
  factory UpgradeDeps.example({bool? major}) =>
      UpgradeDeps(major: major ?? false);

  // ...........................................................................
  /// Allows major version jumps.
  final bool major;

  // ...........................................................................
  /// Upgrades the dependencies of [directory].
  Future<void> apply({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final upgrade = _doUpgradeDeps ?? gg.DoUpgradeDeps(ggLog: ggLog);
    await upgrade.get(directory: directory, ggLog: ggLog, majorVersions: major);
  }

  // ...........................................................................
  final gg.DoUpgradeDeps? _doUpgradeDeps;
}
