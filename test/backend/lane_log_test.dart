// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('LaneLog', () {
    late List<String> lines;
    setUp(() => lines = []);

    String prefixed(String line) => '${darkGray('[ggsuite/gg_json]')} $line';

    test('prefixes every line', () {
      LaneLog.example(lines: lines)('one\ntwo');
      expect(lines, [prefixed('one'), prefixed('two')]);
    });

    test('drops empty lines and running status lines', () {
      LaneLog.example(lines: lines)('\n⌛️ Running tests\n  \ndone');
      expect(lines, [prefixed('done')]);
    });

    test('removes cursor movements of a status printer', () {
      LaneLog.example(lines: lines)('\x1B[1A\x1B[2K✓ Running tests\r');
      expect(lines, [prefixed('✓ Running tests')]);
    });

    test('example logs nowhere without lines', () {
      expect(() => LaneLog.example()('x'), returnsNormally);
      expect(LaneLog.example(prefix: 'p').prefix, 'p');
    });

    test('appends the lines without prefix to the file', () {
      final dir = Directory.systemTemp.createTempSync('lane_log_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(path.join(dir.path, 'repo.log'));
      final log = LaneLog(prefix: 'r', ggLog: lines.add, file: file);
      log('a');
      log('b\nc');
      expect(file.readAsStringSync(), 'a\nb\nc\n');
      expect(log.file, file);
      expect(lines, hasLength(3));
    });

    test('clean keeps colors', () {
      expect(LaneLog.clean(red('x')), red('x'));
    });
  });
}
