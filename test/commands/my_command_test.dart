// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart' show CommandRunner;
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart' show expect, group, test;

void main() {
  group('MyCommand', () {
    test('logs the input', () async {
      final messages = <String>[];
      final runner = CommandRunner<dynamic>('test', 'test')
        ..addCommand(MyCommand.example(ggLog: messages.add));

      await runner.run(['my-command', '--input', 'hello']);
      expect(messages, ['hello']);
    });
  });
}
