// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart' show contains, expect, group, test;

void main() {
  group('GgMultiMaintain', () {
    test('offers maintain', () {
      final command = GgMultiMaintain.example();
      expect(command.name, 'gg_multi_maintain');
      expect(command.description, contains('gg_multi_maintain'));
      expect(command.subcommands.keys, ['maintain']);
    });
  });
}
