// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final rule = VersionIncrement.example();

  Manifests pubspec(String dependencies, {String dev = ''}) => (
    pubspec: 'name: x\ndependencies:\n$dependencies\ndev_dependencies:\n$dev',
    packageJson: null,
  );

  Manifests packageJson(Map<String, Object?> dependencies) => (
    pubspec: null,
    packageJson: jsonEncode({'name': 'x', 'dependencies': dependencies}),
  );

  String derive(Manifests before, Manifests after) =>
      rule.derive(before: before, after: after);

  group('VersionIncrement', () {
    group('read', () {
      test('reads both manifests', () {
        final dir = Directory.systemTemp.createTempSync('version_increment_');
        addTearDown(() => dir.deleteSync(recursive: true));
        File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: x');
        File(path.join(dir.path, 'package.json')).writeAsStringSync('{}');
        expect(VersionIncrement.read(dir), (
          pubspec: 'name: x',
          packageJson: '{}',
        ));
      });

      test('returns null for missing manifests', () {
        final dir = Directory.systemTemp.createTempSync('version_increment_');
        addTearDown(() => dir.deleteSync(recursive: true));
        expect(VersionIncrement.read(dir), (pubspec: null, packageJson: null));
      });
    });

    group('derive', () {
      test('is minor when a dependency jumps a major version', () {
        expect(derive(pubspec('  a: ^1.0.0'), pubspec('  a: ^2.0.0')), 'minor');
      });

      test('is minor when a hosted dependency jumps', () {
        expect(
          derive(
            pubspec('  a:\n    hosted: https://pub.dev\n    version: ^0.1.0'),
            pubspec('  a:\n    hosted: https://pub.dev\n    version: ^0.2.0'),
          ),
          'minor',
        );
      });

      test('is patch for a compatible upgrade', () {
        expect(derive(pubspec('  a: ^1.0.0'), pubspec('  a: ^1.2.0')), 'patch');
      });

      test('is patch when a dev dependency jumps', () {
        expect(
          derive(
            pubspec('  a: ^1.0.0', dev: '  b: ^1.0.0'),
            pubspec('  a: ^1.0.0', dev: '  b: ^2.0.0'),
          ),
          'patch',
        );
      });

      test('is patch for a new dependency', () {
        expect(
          derive(pubspec('  a: ^1.0.0'), pubspec('  a: ^1.0.0\n  b: ^1.0.0')),
          'patch',
        );
      });

      test('ignores a path dependency', () {
        expect(
          derive(
            pubspec('  a:\n    path: ../a'),
            pubspec('  a:\n    path: ../b'),
          ),
          'patch',
        );
      });

      test('ignores an unreadable constraint', () {
        expect(derive(pubspec('  a: ^1.0.0'), pubspec('  a: ~>2')), 'patch');
      });

      test('ignores a new constraint that is no range', () {
        expect(
          derive(pubspec('  a: ^1.0.0'), pubspec('  a: ">=2.0.0 <1.0.0"')),
          'patch',
        );
      });

      test('ignores a new constraint without lower bound', () {
        expect(derive(pubspec('  a: ^1.0.0'), pubspec('  a: any')), 'patch');
      });

      test('is minor when an npm dependency jumps', () {
        expect(
          derive(packageJson({'a': '^1.0.0'}), packageJson({'a': '^2.0.0'})),
          'minor',
        );
      });

      test('ignores npm dependencies that are no strings', () {
        expect(derive(packageJson({'a': 1}), packageJson({'a': 2})), 'patch');
      });

      test('is patch without dependencies', () {
        expect(
          derive(
            (pubspec: 'name: x', packageJson: '{}'),
            (pubspec: 'name: x', packageJson: '{}'),
          ),
          'patch',
        );
      });

      test('is patch without manifests', () {
        expect(
          derive(
            (pubspec: null, packageJson: null),
            (pubspec: null, packageJson: null),
          ),
          'patch',
        );
      });
    });
  });
}
