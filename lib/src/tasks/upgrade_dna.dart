// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../backend/shell.dart';

// #############################################################################
/// Raises the DNA layers of a repo to their newest versions.
///
/// The layers are the packages `dna/_generated.json` lists, plus the helix
/// engine. The direct ones are upgraded across major versions, so a pin like
/// `^0.1.0` moves on; the ones that only come through another layer are
/// unlocked as well. Afterwards the repo's own DNA test regenerates the DNA
/// with the new layers and commits it as `#gg: generated DNA`.
class UpgradeDna {
  /// Constructor
  const UpgradeDna({this._shell = const Shell()});

  /// Upgrades with real processes.
  factory UpgradeDna.example() => const UpgradeDna();

  // ...........................................................................
  /// Upgrades the DNA of [directory]; does nothing for a repo without DNA.
  Future<void> apply({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final layers = layersOf(directory);
    if (layers == null) {
      ggLog('The repo has no DNA.');
      return;
    }
    await _upgradeDart(directory, layers, ggLog);
    await _upgradeTypeScript(directory, layers, ggLog);
    await _regenerate(directory, ggLog);
  }

  // ...........................................................................
  /// Returns the layer packages of [directory] by ecosystem, `pub` or
  /// `node`, or null when the repo has no generated DNA.
  static Map<String, Set<String>>? layersOf(Directory directory) {
    final file = File(path.join(directory.path, 'dna', '_generated.json'));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final result = <String, Set<String>>{'pub': {}, 'node': {}};
    for (final layer in (json['layers'] as List<dynamic>? ?? const [])) {
      final map = layer as Map<String, dynamic>;
      final ecosystem = map['ecosystem'] as String?;
      result[ecosystem]?.add(map['package'] as String);
    }
    return result;
  }

  // ...........................................................................
  final Shell _shell;

  // ...........................................................................
  Future<void> _upgradeDart(
    Directory directory,
    Map<String, Set<String>> layers,
    GgLog ggLog,
  ) async {
    final pubspec = File(path.join(directory.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;
    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    final declared = {
      ...((yaml['dependencies'] as YamlMap?)?.keys ?? const []),
      ...((yaml['dev_dependencies'] as YamlMap?)?.keys ?? const []),
    }.cast<String>();
    final wanted = {...layers['pub']!, 'helix'};
    final direct = wanted.where(declared.contains).toList()..sort();
    final indirect = layers['pub']!.where((p) => !declared.contains(p)).toList()
      ..sort();
    final pub = _isFlutter(directory) ? 'flutter' : 'dart';

    if (direct.isNotEmpty) {
      await _shell.run(pub, [
        'pub',
        'upgrade',
        '--major-versions',
        ...direct,
      ], directory: directory);
      ggLog('Upgraded ${direct.join(', ')}.');
    }
    if (indirect.isNotEmpty) {
      await _shell.run(pub, [
        'pub',
        'upgrade',
        ...indirect,
      ], directory: directory);
      ggLog('Upgraded ${indirect.join(', ')}.');
    }
  }

  // ...........................................................................
  Future<void> _upgradeTypeScript(
    Directory directory,
    Map<String, Set<String>> layers,
    GgLog ggLog,
  ) async {
    final file = File(path.join(directory.path, 'package.json'));
    if (!file.existsSync()) return;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final declared = {
      ...((json['dependencies'] as Map<String, dynamic>?)?.keys ?? const []),
      ...((json['devDependencies'] as Map<String, dynamic>?)?.keys ?? const []),
    };
    final direct =
        declared
            .where((p) => layers['node']!.contains(p) || _isHelixJs(p))
            .toList()
          ..sort();
    if (direct.isEmpty) return;
    final update = detectTypeScriptPackageManager(directory)
        .updateCommand(latest: true);
    await _shell.run(update.executable, [
      ...update.args,
      ...direct,
    ], directory: directory);
    ggLog('Upgraded ${direct.join(', ')}.');
  }

  // ...........................................................................
  Future<void> _regenerate(Directory directory, GgLog ggLog) async {
    final dartTest = path.join('test', 'dna', 'dna_test.dart');
    final tsTest = path.join('test', 'dna', 'dna.spec.ts');
    if (File(path.join(directory.path, dartTest)).existsSync()) {
      await _shell.run(_isFlutter(directory) ? 'flutter' : 'dart', [
        'test',
        dartTest,
      ], directory: directory);
    } else if (File(path.join(directory.path, tsTest)).existsSync()) {
      final vitest = detectTypeScriptPackageManager(directory)
          .execCommand('vitest', [
            'run',
            tsTest,
            // One test file never meets the coverage thresholds of a repo.
            '--coverage.enabled=false',
          ]);
      await _shell.run(vitest.executable, vitest.args, directory: directory);
    } else {
      ggLog('The repo has no DNA test; the DNA is not regenerated.');
      return;
    }
    ggLog('Regenerated the DNA.');
  }

  // ...........................................................................
  static bool _isFlutter(Directory directory) =>
      detectProjectType(directory) == ProjectType.flutter;

  static bool _isHelixJs(String package) =>
      package == 'helix-js' || package.endsWith('/helix-js');
}
