// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:test/test.dart';

// #############################################################################
/// Records the calls instead of upgrading.
class _RecordingUpgrade extends gg.DoUpgradeDeps {
  _RecordingUpgrade() : super(ggLog: (_) {});

  final calls = <(Directory, bool?)>[];

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) async => calls.add((directory, majorVersions));
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('upgrade_deps_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('UpgradeDeps', () {
    test('example does not jump major versions', () {
      expect(UpgradeDeps.example().major, isFalse);
      expect(UpgradeDeps.example(major: true).major, isTrue);
    });

    group('apply', () {
      for (final major in [false, true]) {
        test('passes major: $major to the upgrade', () async {
          final upgrade = _RecordingUpgrade();
          await UpgradeDeps(
            major: major,
            doUpgradeDeps: upgrade,
          ).apply(directory: dir, ggLog: (_) {});
          expect(upgrade.calls, [(dir, major)]);
        });
      }

      test('runs gg one do upgrade deps by default', () async {
        final messages = <String>[];
        await UpgradeDeps.example().apply(directory: dir, ggLog: messages.add);
        expect(messages, [contains('No pubspec.yaml and no package.json')]);
      });
    });
  });
}
