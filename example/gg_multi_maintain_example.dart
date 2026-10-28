#!/usr/bin/env dart

// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart' show CommandRunner;

Future<void> main() async {
  await CommandRunner<dynamic>('gg_multi_maintain', 'Example').run(['help']);
}
