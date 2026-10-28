// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// The manifests of a repo, to compare them before and after maintenance.
typedef Manifests = ({String? pubspec, String? packageJson});

// #############################################################################
/// Derives the version increment from what maintenance changed.
///
/// A regular dependency whose new lower bound the old constraint does not
/// allow means consumers get a breaking upgrade with it: that is a minor
/// release. Everything else, dev dependencies and the SDK included, is a
/// patch.
class VersionIncrement {
  /// Constructor
  const VersionIncrement();

  /// The rule as used by `gg do maintain`.
  factory VersionIncrement.example() => const VersionIncrement();

  // ...........................................................................
  /// Reads the manifests of [directory].
  static Manifests read(Directory directory) {
    String? content(String name) {
      final file = File(path.join(directory.path, name));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    return (
      pubspec: content('pubspec.yaml'),
      packageJson: content('package.json'),
    );
  }

  // ...........................................................................
  /// Returns `minor` or `patch` for the change from [before] to [after].
  String derive({required Manifests before, required Manifests after}) {
    final dependencies = [
      (
        _pubspecDependencies(before.pubspec),
        _pubspecDependencies(after.pubspec),
      ),
      (
        _npmDependencies(before.packageJson),
        _npmDependencies(after.packageJson),
      ),
    ];
    for (final (old, current) in dependencies) {
      for (final MapEntry(:key, :value) in current.entries) {
        if (_isBreaking(old[key], value)) return 'minor';
      }
    }
    return 'patch';
  }

  // ...........................................................................
  bool _isBreaking(String? old, String current) {
    if (old == null) return false;
    try {
      final oldConstraint = VersionConstraint.parse(old);
      final newConstraint = VersionConstraint.parse(current);
      if (newConstraint is! VersionRange) return false;
      final min = newConstraint.min;
      return min != null && !oldConstraint.allows(min);
    } on FormatException {
      return false;
    }
  }

  // ...........................................................................
  Map<String, String> _pubspecDependencies(String? pubspec) {
    if (pubspec == null) return const {};
    final yaml = loadYaml(pubspec) as YamlMap;
    final dependencies = yaml['dependencies'] as YamlMap?;
    return {
      for (final MapEntry(:key, :value) in (dependencies?.entries ?? const []))
        if (_versionOf(value) case final String version) key as String: version,
    };
  }

  // ...........................................................................
  String? _versionOf(Object? value) => switch (value) {
    final String version => version,
    final YamlMap map when map['version'] is String => map['version'] as String,
    _ => null,
  };

  // ...........................................................................
  Map<String, String> _npmDependencies(String? packageJson) {
    if (packageJson == null) return const {};
    final json = jsonDecode(packageJson) as Map<String, dynamic>;
    return {
      for (final MapEntry(:key, :value)
          in (json['dependencies'] as Map<String, dynamic>? ?? const {})
              .entries)
        if (value is String) key: value,
    };
  }
}
