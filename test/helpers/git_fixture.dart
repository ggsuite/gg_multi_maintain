// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// #############################################################################
/// Real git repositories for the tests: no network, no mocks.
class GitFixture {
  /// Creates a fixture in a fresh temp folder that is deleted after the test.
  GitFixture() : root = Directory.systemTemp.createTempSync('gg_maintain') {
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold a file; the temp folder is cleaned later.
      }
    });
  }

  /// The temp folder everything lives in.
  final Directory root;

  /// The ocean of the fake workspace.
  Directory get ocean =>
      Directory(path.join(root.path, 'workspace', '.ocean'))
        ..createSync(recursive: true);

  // ...........................................................................
  /// Creates a bare remote named [name] whose main holds [files].
  String remote(String name, Map<String, String> files) {
    final work = Directory(path.join(root.path, 'work', name))
      ..createSync(recursive: true);
    writeFiles(work, files);
    git(work, ['init', '-q', '-b', 'main']);
    git(work, ['add', '.']);
    git(work, ['commit', '-q', '-m', 'Initial']);
    final bare = path.join(root.path, 'remotes', '$name.git');
    git(root, ['clone', '-q', '--bare', work.path, bare]);
    return bare;
  }

  // ...........................................................................
  /// Creates `.ocean/<org>/<name>` with [files] and [url] as origin.
  Directory oceanRepo(
    String org,
    String name, {
    Map<String, String>? files,
    String? url,
  }) {
    final dir = Directory(path.join(ocean.path, org, name))
      ..createSync(recursive: true);
    writeFiles(dir, files ?? {'pubspec.yaml': pubspec(name)});
    git(dir, ['init', '-q', '-b', 'main']);
    if (url != null) git(dir, ['remote', 'add', 'origin', url]);
    return dir;
  }

  // ...........................................................................
  /// Writes [files] below [dir].
  static void writeFiles(Directory dir, Map<String, String> files) {
    for (final MapEntry(:key, :value) in files.entries) {
      File(path.join(dir.path, key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(value);
    }
  }

  // ...........................................................................
  /// Runs git in [dir] and returns its trimmed stdout.
  static String git(Directory dir, List<String> args) {
    final result = Process.runSync('git', [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.com',
      ...args,
    ], workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw Exception('git ${args.join(' ')}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  // ...........................................................................
  /// A minimal pubspec of [name].
  static String pubspec(
    String name, {
    String version = '1.0.0',
    Map<String, String> dependencies = const {},
    Map<String, String> devDependencies = const {},
  }) {
    String block(String title, Map<String, String> entries) {
      if (entries.isEmpty) return '';
      final lines = entries.entries.map((e) => '  ${e.key}: ${e.value}\n');
      return '$title:\n${lines.join()}';
    }

    return 'name: $name\n'
        'version: $version\n'
        'environment:\n'
        '  sdk: ">=3.0.0 <4.0.0"\n'
        '${block('dependencies', dependencies)}'
        '${block('dev_dependencies', devDependencies)}';
  }

  /// The files of a Dart package without dependencies.
  static Map<String, String> dartPackage(String name) => {
    'pubspec.yaml': pubspec(name),
    '.gitignore': '.dart_tool/\n',
  };
}
