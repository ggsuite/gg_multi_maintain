// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../../bin/gg_multi_maintain.dart';

import 'package:test/test.dart' show expect, group, test;

void main() {
  group('bin/gg_multi_maintain.dart', () {
    test('runs my-command', () async {
      final messages = <String>[];
      await run(args: ['my-command', '-i', 'hello'], ggLog: messages.add);
      expect(messages, ['hello']);
    });
  });
}
