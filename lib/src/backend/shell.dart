// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_process/gg_process.dart';

// #############################################################################
/// Runs a command in a repo and throws when it fails.
class Shell {
  /// Constructor
  const Shell({this._processWrapper = const GgProcessWrapper()});

  /// A shell running real processes.
  factory Shell.example() => const Shell();

  // ...........................................................................
  /// Runs [executable] with [args] in [directory] and returns its stdout.
  Future<String> run(
    String executable,
    List<String> args, {
    required Directory directory,
  }) async {
    final result = await _processWrapper.run(
      executable,
      args,
      workingDirectory: directory.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw Exception(
        '»$executable ${args.join(' ')}« failed:\n'
                '${result.stderr}${result.stdout}'
            .trim(),
      );
    }
    return result.stdout as String;
  }

  // ...........................................................................
  final GgProcessWrapper _processWrapper;
}
