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

// #############################################################################
/// Records the commands instead of running them.
class _FakeShell implements Shell {
  final calls = <List<String>>[];

  @override
  Future<String> run(
    String executable,
    List<String> args, {
    required Directory directory,
  }) async {
    calls.add([executable, ...args]);
    return '';
  }
}

void main() {
  late Directory dir;
  late List<String> messages;
  late _FakeShell shell;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('upgrade_dna_test_');
    messages = [];
    shell = _FakeShell();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name, String content) {
    final file = File(path.join(dir.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writeLayers(List<Map<String, Object?>> layers) => write(
    path.join('dna', '_generated.json'),
    jsonEncode({'version': 1, 'layers': layers}),
  );

  Map<String, Object?> layer(String package, String? ecosystem) => {
    'name': package,
    'package': package,
    'ecosystem': ecosystem,
  };

  Future<void> apply() =>
      UpgradeDna(shell: shell).apply(directory: dir, ggLog: messages.add);

  final dartTest = path.join('test', 'dna', 'dna_test.dart');
  final tsTest = path.join('test', 'dna', 'dna.spec.ts');

  group('UpgradeDna', () {
    test('example creates an upgrader', () {
      expect(UpgradeDna.example(), isA<UpgradeDna>());
    });

    group('layersOf', () {
      test('returns null without generated DNA', () {
        expect(UpgradeDna.layersOf(dir), isNull);
      });

      test('groups the layer packages by ecosystem', () {
        writeLayers([
          layer('helix', null),
          layer('dna_gg', 'pub'),
          layer('@ggdna/dna-readme', 'node'),
          layer('other', 'maven'),
        ]);
        expect(UpgradeDna.layersOf(dir), {
          'pub': {'dna_gg'},
          'node': {'@ggdna/dna-readme'},
        });
      });

      test('returns empty sets without layers', () {
        write(path.join('dna', '_generated.json'), '{"version": 1}');
        expect(UpgradeDna.layersOf(dir), {
          'pub': <String>{},
          'node': <String>{},
        });
      });
    });

    group('apply', () {
      test('does nothing without DNA', () async {
        await apply();
        expect(shell.calls, isEmpty);
        expect(messages, ['The repo has no DNA.']);
      });

      test('upgrades the Dart layers and regenerates the DNA', () async {
        writeLayers([
          layer('helix', null),
          layer('dna_ggsuite', 'pub'),
          layer('dna_gg', 'pub'),
          layer('dna_readme', 'pub'),
        ]);
        write(
          'pubspec.yaml',
          'name: x\n'
              'dependencies:\n  path: ^1.0.0\n'
              'dev_dependencies:\n  dna_ggsuite: ^1.0.0\n  helix: ^1.0.0\n',
        );
        write(dartTest, '');
        await apply();
        expect(shell.calls, [
          [
            'dart',
            'pub',
            'upgrade',
            '--major-versions',
            'dna_ggsuite',
            'helix',
          ],
          ['dart', 'pub', 'upgrade', 'dna_gg', 'dna_readme'],
          ['dart', 'test', dartTest],
        ]);
        expect(messages, [
          'Upgraded dna_ggsuite, helix.',
          'Upgraded dna_gg, dna_readme.',
          'Regenerated the DNA.',
        ]);
      });

      test('uses flutter in a Flutter package', () async {
        writeLayers([layer('dna_ggsuite', 'pub')]);
        write(
          'pubspec.yaml',
          'name: x\n'
              'dev_dependencies:\n  dna_ggsuite: ^1.0.0\n'
              'flutter:\n  uses-material-design: true\n',
        );
        write(dartTest, '');
        await apply();
        expect(shell.calls, [
          ['flutter', 'pub', 'upgrade', '--major-versions', 'dna_ggsuite'],
          ['flutter', 'test', dartTest],
        ]);
      });

      test('upgrades nothing in a pubspec without layers', () async {
        writeLayers([layer('helix', null)]);
        write('pubspec.yaml', 'name: x\n');
        await apply();
        expect(shell.calls, isEmpty);
        expect(messages, [
          'The repo has no DNA test; the DNA is not regenerated.',
        ]);
      });

      test('upgrades the TypeScript layers with pnpm', () async {
        writeLayers([
          layer('helix', null),
          layer('@tssuite/dna-tssuite', 'node'),
          layer('@ggdna/dna-readme', 'node'),
        ]);
        write(
          'package.json',
          jsonEncode({
            'name': 'x',
            'dependencies': {'helix-js': '^1.0.0', 'left-pad': '^1.0.0'},
            'devDependencies': {
              '@tssuite/helix-js': '^0.1.0',
              '@tssuite/dna-tssuite': '^0.1.0',
            },
          }),
        );
        write('pnpm-lock.yaml', '');
        write(tsTest, '');
        await apply();
        expect(shell.calls, [
          [
            'pnpm',
            'update',
            '--latest',
            '@tssuite/dna-tssuite',
            '@tssuite/helix-js',
            'helix-js',
          ],
          ['pnpm', 'exec', 'vitest', 'run', tsTest, '--coverage.enabled=false'],
        ]);
        expect(messages, [
          'Upgraded @tssuite/dna-tssuite, @tssuite/helix-js, helix-js.',
          'Regenerated the DNA.',
        ]);
      });

      test('upgrades nothing in a package.json without layers', () async {
        writeLayers([layer('@tssuite/dna-tssuite', 'node')]);
        write('package.json', '{"name": "x"}');
        await apply();
        expect(shell.calls, isEmpty);
      });
    });
  });
}
