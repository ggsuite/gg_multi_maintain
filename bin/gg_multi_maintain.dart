#!/usr/bin/env dart

// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_args/gg_args.dart' show GgCommandRunner;
import 'package:gg_log/gg_log.dart' show GgLog;
import 'package:gg_multi_maintain/gg_multi_maintain.dart';

// .............................................................................
/// Runs gg_multi_maintain with [args].
Future<void> run({required List<String> args, required GgLog ggLog}) =>
    GgCommandRunner(
      ggLog: ggLog,
      command: GgMultiMaintain(ggLog: ggLog),
    ).run(args: args);

// .............................................................................
Future<void> main(List<String> args) async {
  await run(args: args, ggLog: print);
}
