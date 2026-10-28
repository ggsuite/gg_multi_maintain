// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late List<String> messages;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('upgrade_sdk_test_');
    messages = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name, String content) =>
      File(path.join(dir.path, name)).writeAsStringSync(content);

  String read(String name) =>
      File(path.join(dir.path, name)).readAsStringSync();

  group('UpgradeSdk', () {
    group('raisedDartConstraint', () {
      final installed = Version(3, 14, 2);
      String? raise(String current, [Version? version]) =>
          UpgradeSdk.raisedDartConstraint(current, version ?? installed);

      test('raises a double quoted range', () {
        expect(raise('">=3.13.0 <4.0.0"'), '">=3.14.0 <4.0.0"');
      });

      test('raises a single quoted range', () {
        expect(raise("'>=3.13.0 <4.0.0'"), '">=3.14.0 <4.0.0"');
      });

      test('raises an unquoted range', () {
        expect(raise('>=3.0.0 <4.0.0'), '">=3.14.0 <4.0.0"');
      });

      test('turns a caret into a range without the pre-release', () {
        expect(raise('^3.5.0'), '">=3.14.0 <4.0.0"');
      });

      test('keeps an upper bound that is a real pre-release', () {
        expect(raise('>=3.0.0 <4.0.0-1'), '">=3.14.0 <4.0.0-1"');
      });

      test('keeps an inclusive upper bound', () {
        expect(raise('>=3.0.0 <=3.20.0'), '">=3.14.0 <=3.20.0"');
      });

      test('replaces an upper bound below the new lower bound', () {
        expect(raise('>=3.0.0 <3.10.0'), '">=3.14.0 <4.0.0"');
      });

      test('bounds »any«', () {
        expect(raise('any'), '">=3.14.0 <4.0.0"');
      });

      test('starts a pre-release SDK at its first pre-release', () {
        expect(
          raise('">=3.13.0 <4.0.0"', Version.parse('3.15.0-12.0.dev')),
          '">=3.15.0-0 <4.0.0"',
        );
      });

      test('returns null when the range already starts high enough', () {
        expect(raise('">=3.14.0 <4.0.0"', Version(3, 14, 5)), isNull);
      });

      test('returns null for an unreadable constraint', () {
        expect(raise('not a constraint'), isNull);
      });

      test('returns null for an empty constraint', () {
        expect(raise('>=2.0.0 <1.0.0'), isNull);
      });
    });

    group('raisedNodeConstraint', () {
      final installed = Version(24, 1, 0);
      String? raise(String current, [Version? version]) =>
          UpgradeSdk.raisedNodeConstraint(current, version ?? installed);

      test('raises a full version', () {
        expect(raise('>=22.14.0'), '>=24.1.0');
      });

      test('raises a major only and keeps it a major only', () {
        expect(raise('>=22'), '>=24');
      });

      test('raises a version with a v and two parts', () {
        expect(raise(' >=v22.1 '), '>=24.1.0');
      });

      test('returns null for a major only that is up to date', () {
        expect(raise('>=24'), isNull);
      });

      test('returns null for a full version that is up to date', () {
        expect(raise('>=24.1.0', Version(24, 1, 3)), isNull);
      });

      test('returns null for a constraint other than >=', () {
        expect(raise('^22'), isNull);
      });
    });

    group('apply', () {
      Future<bool> apply([UpgradeSdk? sdk]) => (sdk ?? UpgradeSdk.example())
          .apply(directory: dir, ggLog: messages.add);

      test('raises the Dart SDK and keeps comments', () async {
        write(
          'pubspec.yaml',
          'name: x\n'
              'environment:\n'
              '  # The SDK\n'
              '\n'
              '  sdk: ">=3.13.0 <4.0.0" # keep\n'
              'dependencies: {}\n',
        );
        expect(await apply(), isTrue);
        expect(
          read('pubspec.yaml'),
          'name: x\n'
          'environment:\n'
          '  # The SDK\n'
          '\n'
          '  sdk: ">=3.14.0 <4.0.0" # keep\n'
          'dependencies: {}\n',
        );
        expect(messages, [
          'Raised the Dart SDK from ">=3.13.0 <4.0.0" to ">=3.14.0 <4.0.0".',
        ]);
      });

      test('raises the Dart SDK in a file with CRLF line endings', () async {
        write(
          'pubspec.yaml',
          'name: x\r\nenvironment:\r\n  sdk: ">=3.13.0 <4.0.0"\r\n',
        );
        expect(await apply(), isTrue);
        expect(
          read('pubspec.yaml'),
          'name: x\r\nenvironment:\r\n  sdk: ">=3.14.0 <4.0.0"\r\n',
        );
      });

      test('leaves an up to date pubspec alone', () async {
        const content = 'name: x\nenvironment:\n  sdk: ">=3.14.0 <4.0.0"\n';
        write('pubspec.yaml', content);
        expect(await apply(), isFalse);
        expect(read('pubspec.yaml'), content);
        expect(messages, ['The SDK constraints are up to date.']);
      });

      test('leaves a pubspec without environment alone', () async {
        write('pubspec.yaml', 'name: x\n');
        expect(await apply(), isFalse);
        expect(read('pubspec.yaml'), 'name: x\n');
      });

      test('does nothing without manifests', () async {
        expect(await apply(), isFalse);
        expect(messages, ['The SDK constraints are up to date.']);
      });

      test('raises engines.node', () async {
        write(
          'package.json',
          '{\n  "name": "x",\n  "engines": {\n'
              '    "node": ">=22.14.0"\n  }\n}\n',
        );
        expect(await apply(), isTrue);
        expect(
          read('package.json'),
          '{\n  "name": "x",\n  "engines": {\n    "node": ">=24.1.0"\n  }\n}\n',
        );
        expect(messages, ['Raised Node from >=22.14.0 to >=24.1.0.']);
      });

      test('raises a major only engines.node', () async {
        write('package.json', '{"engines": {"npm": ">=10", "node": ">=22"}}');
        expect(await apply(), isTrue);
        expect(
          read('package.json'),
          '{"engines": {"npm": ">=10", "node": ">=24"}}',
        );
      });

      test('leaves a package.json without engines alone', () async {
        write('package.json', '{"name": "x", "node": ">=1"}');
        expect(await apply(), isFalse);
        expect(read('package.json'), '{"name": "x", "node": ">=1"}');
      });

      test('leaves engines without node alone', () async {
        write('package.json', '{"engines": {"npm": ">=10"}}');
        expect(await apply(), isFalse);
      });

      test('leaves an engines.node other than >= alone', () async {
        write('package.json', '{"engines": {"node": "^22"}}');
        expect(await apply(), isFalse);
        expect(read('package.json'), '{"engines": {"node": "^22"}}');
      });

      test('raises both sides of a hybrid', () async {
        write('pubspec.yaml', 'environment:\n  sdk: ^3.0.0\n');
        write('package.json', '{"engines": {"node": ">=20"}}');
        expect(await apply(), isTrue);
        expect(
          read('pubspec.yaml'),
          'environment:\n  sdk: ">=3.14.0 <4.0.0"\n',
        );
        expect(read('package.json'), '{"engines": {"node": ">=24"}}');
        expect(messages, hasLength(2));
      });

      test('reads the installed Dart and Node by default', () async {
        write(
          'pubspec.yaml',
          'name: x\nenvironment:\n  sdk: ">=1.0.0 <9.0.0"\n',
        );
        write('package.json', '{"engines": {"node": ">=1"}}');
        expect(await apply(UpgradeSdk()), isTrue);

        final dart = Version.parse(Platform.version.split(' ').first);
        expect(
          read('pubspec.yaml'),
          'name: x\nenvironment:\n'
          '  sdk: ">=${dart.major}.${dart.minor}.0'
          '${dart.isPreRelease ? '-0' : ''} <9.0.0"\n',
        );
        expect(
          read('package.json'),
          matches(RegExp(r'^\{"engines": \{"node": ">=\d+"\}\}$')),
        );
      });
    });
  });
}
