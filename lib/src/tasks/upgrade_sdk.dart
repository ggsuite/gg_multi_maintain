// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../backend/shell.dart';

// #############################################################################
/// Reads the version of an installed tool.
typedef ToolVersion = Future<Version> Function(Directory directory);

// #############################################################################
/// Raises the SDK constraint of a repo to the installed SDK.
///
/// Dart repos get the lower bound of `environment: sdk:` raised to the
/// installed Dart (Flutter repos: the Dart of the installed Flutter), in the
/// form `">=3.14.0 <4.0.0"`. TypeScript repos get `engines.node` raised to
/// the installed Node, keeping the precision they had (`>=24` stays a major
/// only). A constraint is never lowered and never added where it is missing.
class UpgradeSdk {
  /// Constructor
  UpgradeSdk({
    Shell shell = const Shell(),
    ToolVersion? dartVersion,
    ToolVersion? nodeVersion,
  }) : _dartVersion = dartVersion ?? _installedDart(shell),
       _nodeVersion = nodeVersion ?? _installedNode(shell);

  /// Upgrades to Dart 3.14.0 and Node 24.1.0.
  factory UpgradeSdk.example({Version? dart, Version? node}) => UpgradeSdk(
    dartVersion: (_) async => dart ?? Version(3, 14, 0),
    nodeVersion: (_) async => node ?? Version(24, 1, 0),
  );

  // ...........................................................................
  /// Upgrades the constraints in [directory] and returns whether one changed.
  Future<bool> apply({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final dart = await _upgradePubspec(directory, ggLog);
    final node = await _upgradePackageJson(directory, ggLog);
    if (!dart && !node) ggLog('The SDK constraints are up to date.');
    return dart || node;
  }

  // ...........................................................................
  /// Returns the constraint that admits [installed] as lowest version, or
  /// null when [current] already starts at or above it.
  static String? raisedDartConstraint(String current, Version installed) {
    final lower = Version(
      installed.major,
      installed.minor,
      0,
      pre: installed.isPreRelease ? '0' : null,
    );
    final VersionConstraint constraint;
    try {
      constraint = VersionConstraint.parse(_unquote(current));
    } on FormatException {
      return null;
    }
    if (constraint is! VersionRange) return null;
    final min = constraint.min;
    if (min != null && min >= lower) return null;
    final max = constraint.max;
    final upper = max != null && max > lower
        ? '${constraint.includeMax ? '<=' : '<'}${_withoutFirstPre(max)}'
        : '<${installed.major + 1}.0.0';
    return '">=$lower $upper"';
  }

  // ...........................................................................
  /// Returns the raised `engines.node` value, or null when [current] is not
  /// a `>=` constraint or already starts at or above [installed].
  static String? raisedNodeConstraint(String current, Version installed) {
    final match = _nodeRange.firstMatch(current.trim());
    if (match == null) return null;
    final majorOnly = match.group(2) == null;
    final old = Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
    );
    final raised = majorOnly
        ? '>=${installed.major}'
        : '>=${installed.major}.${installed.minor}.0';
    final lower = Version(installed.major, majorOnly ? 0 : installed.minor, 0);
    return old >= lower ? null : raised;
  }

  // ...........................................................................
  final ToolVersion _dartVersion;
  final ToolVersion _nodeVersion;

  static final _sdkLine = RegExp(
    r'^(environment:[ \t]*\r?\n(?:[ \t]*(?:#.*)?\r?\n|[ \t]+.*\r?\n)*?'
    r'[ \t]+sdk:[ \t]*)([^\r\n#]*?)([ \t]*(?:#[^\r\n]*)?)(?=\r?$)',
    multiLine: true,
  );
  static final _engines = RegExp(r'"engines"\s*:\s*\{[^}]*\}');
  static final _nodeEntry = RegExp(r'("node"\s*:\s*")([^"]*)(")');
  static final _nodeRange = RegExp(r'^>=\s*v?(\d+)(?:\.(\d+))?(?:\.(\d+))?$');

  // ...........................................................................
  Future<bool> _upgradePubspec(Directory directory, GgLog ggLog) async {
    final file = File(path.join(directory.path, 'pubspec.yaml'));
    if (!file.existsSync()) return false;
    final content = file.readAsStringSync();
    final match = _sdkLine.firstMatch(content);
    if (match == null) return false;
    final installed = await _dartVersion(directory);
    final raised = raisedDartConstraint(match.group(2)!, installed);
    if (raised == null) return false;
    file.writeAsStringSync(
      content.replaceRange(
        match.start,
        match.end,
        '${match.group(1)}$raised${match.group(3)}',
      ),
    );
    ggLog('Raised the Dart SDK from ${match.group(2)} to $raised.');
    return true;
  }

  // ...........................................................................
  Future<bool> _upgradePackageJson(Directory directory, GgLog ggLog) async {
    final file = File(path.join(directory.path, 'package.json'));
    if (!file.existsSync()) return false;
    final content = file.readAsStringSync();
    final engines = _engines.firstMatch(content);
    final node = engines == null
        ? null
        : _nodeEntry.firstMatch(engines.group(0)!);
    if (engines == null || node == null) return false;
    final installed = await _nodeVersion(directory);
    final raised = raisedNodeConstraint(node.group(2)!, installed);
    if (raised == null) return false;
    file.writeAsStringSync(
      content.replaceRange(
        engines.start + node.start,
        engines.start + node.end,
        '${node.group(1)}$raised${node.group(3)}',
      ),
    );
    ggLog('Raised Node from ${node.group(2)} to $raised.');
    return true;
  }

  // ...........................................................................
  static String _unquote(String value) {
    final trimmed = value.trim();
    final quoted =
        trimmed.length >= 2 &&
        (trimmed.startsWith('"') || trimmed.startsWith("'")) &&
        trimmed.endsWith(trimmed[0]);
    return quoted ? trimmed.substring(1, trimmed.length - 1) : trimmed;
  }

  // ...........................................................................
  static Version _withoutFirstPre(Version version) =>
      version.preRelease.length == 1 && version.preRelease.first == 0
      ? Version(version.major, version.minor, version.patch)
      : version;

  // ...........................................................................
  static ToolVersion _installedDart(Shell shell) => (directory) async {
    if (detectProjectType(directory) != ProjectType.flutter) {
      return _firstVersionIn(Platform.version);
    }
    // coverage:ignore-start
    final machine = await shell.run('flutter', [
      '--version',
      '--machine',
    ], directory: directory);
    final json = jsonDecode(machine) as Map<String, dynamic>;
    return _firstVersionIn(json['dartSdkVersion'] as String);
    // coverage:ignore-end
  };

  // ...........................................................................
  static ToolVersion _installedNode(Shell shell) =>
      (directory) async => _firstVersionIn(
        await shell.run('node', ['--version'], directory: directory),
      );

  // ...........................................................................
  static Version _firstVersionIn(String text) => Version.parse(
    RegExp(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?').firstMatch(text)!.group(0)!,
  );
}
