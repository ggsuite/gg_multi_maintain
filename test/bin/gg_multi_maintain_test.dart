// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../../bin/gg_multi_maintain.dart';

import 'package:test/test.dart' show contains, expect, group, test;

void main() {
  group('bin/gg_multi_maintain.dart', () {
    test('runs maintain', () async {
      final messages = <String>[];
      await run(args: ['maintain'], ggLog: messages.add);
      expect(messages.single, contains('Choose at least one task'));
    });
  });
}
