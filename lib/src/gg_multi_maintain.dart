// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'commands/my_command.dart';

/// The root command of gg_multi_maintain.
class GgMultiMaintain extends Command<dynamic> {
  /// Constructor
  GgMultiMaintain({required this.ggLog}) {
    addSubcommand(MyCommand(ggLog: ggLog));
  }

  /// A command that logs nothing; tests pass what they care about.
  factory GgMultiMaintain.example({GgLog? ggLog}) =>
      GgMultiMaintain(ggLog: ggLog ?? (_) {});

  // ...........................................................................
  @override
  final name = 'gg_multi_maintain';

  @override
  final description =
      'The command line interface of '
      'gg_multi_maintain.';

  /// The log function.
  final GgLog ggLog;
}
