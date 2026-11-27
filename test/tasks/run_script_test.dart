// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/src/tasks/run_script.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('RunScript', () {
    late Directory dir;
    late List<String> log;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('run_script_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      log = [];
    });

    group('commandOf', () {
      test('picks the interpreter by the extension', () {
        List<Object> of(String script) {
          final (executable, args) = RunScript.commandOf(script);
          return [executable, ...args];
        }

        expect(of('/a/m.dart'), ['dart', 'run', '/a/m.dart']);
        expect(of('/a/m.js'), ['node', '/a/m.js']);
        expect(of('/a/m.mjs'), ['node', '/a/m.mjs']);
        expect(of('/a/m.SH'), ['bash', '/a/m.SH']);
        expect(of('/a/m.ps1'), ['pwsh', '-NoProfile', '-File', '/a/m.ps1']);
        expect(of('/a/m'), ['/a/m']);
      });
    });

    group('apply', () {
      test('runs a Dart script in the directory and logs its output', () async {
        final script = File(path.join(dir.path, 'touch.dart'))
          ..writeAsStringSync('''
import 'dart:io';
void main() {
  File('touched.txt').writeAsStringSync('yes');
  print('touched');
  print('');
}
''');
        final repo = Directory(path.join(dir.path, 'repo'))..createSync();
        await RunScript(script: script.path)
            .apply(directory: repo, ggLog: log.add);
        expect(File(path.join(repo.path, 'touched.txt')).existsSync(), isTrue);
        expect(log, ['touched']);
      });

      test('throws when the script fails', () async {
        final script = File(path.join(dir.path, 'fail.dart'))
          ..writeAsStringSync("import 'dart:io'; void main() => exit(3);");
        await expectLater(
          RunScript.example(script: script.path)
              .apply(directory: dir, ggLog: log.add),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
