// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('Shell', () {
    test('returns the stdout of a command', () async {
      final out = await Shell.example().run('git', [
        '--version',
      ], directory: Directory.current);
      expect(out, startsWith('git version'));
    });

    test('throws with the output of a failing command', () async {
      await expectLater(
        Shell.example().run('git', [
          'no-such-command',
        ], directory: Directory.current),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('»git no-such-command« failed'),
          ),
        ),
      );
    });
  });
}
