// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../backend/shell.dart';

// #############################################################################
/// Runs a script in the root of a repo.
///
/// The interpreter follows the extension: `.dart` runs with `dart run`,
/// `.js` and `.mjs` with `node`, `.sh` with `bash`, `.ps1` with `pwsh`.
/// Any other file runs as it is and must be executable. The script fails
/// the repo by exiting with a code other than 0.
class RunScript {
  /// Constructor
  const RunScript({required this.script, this._shell = const Shell()});

  /// Runs `migrate.dart`.
  factory RunScript.example({String? script, Shell? shell}) => RunScript(
    script: script ?? 'migrate.dart',
    shell: shell ?? const Shell(),
  );

  /// The absolute path of the script.
  final String script;

  // ...........................................................................
  /// Runs the script in [directory].
  Future<void> apply({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final (executable, args) = commandOf(script);
    final output = await _shell.run(executable, args, directory: directory);
    for (final line in output.trim().split('\n')) {
      if (line.trim().isNotEmpty) ggLog(line);
    }
  }

  // ...........................................................................
  /// The executable and arguments that run [script].
  static (String, List<String>) commandOf(String script) =>
      switch (path.extension(script).toLowerCase()) {
        '.dart' => ('dart', ['run', script]),
        '.js' || '.mjs' => ('node', [script]),
        '.sh' => ('bash', [script]),
        '.ps1' => ('pwsh', ['-NoProfile', '-File', script]),
        _ => (script, <String>[]),
      };

  // ...........................................................................
  final Shell _shell;
}
