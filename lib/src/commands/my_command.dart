// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

/// Logs the text given with --input.
class MyCommand extends Command<dynamic> {
  /// Constructor
  MyCommand({required this.ggLog}) {
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'The text to log.',
      mandatory: true,
    );
  }

  /// A command that logs nothing; tests pass what they care about.
  factory MyCommand.example({GgLog? ggLog}) =>
      MyCommand(ggLog: ggLog ?? (_) {});

  // ...........................................................................
  @override
  final name = 'my-command';

  @override
  final description = 'Logs the text given with --input.';

  @override
  Future<void> run() async => ggLog(argResults!['input'] as String);

  /// The log function.
  final GgLog ggLog;
}
