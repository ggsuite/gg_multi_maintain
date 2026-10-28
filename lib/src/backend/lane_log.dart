// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';

// #############################################################################
/// The log of one repo while many repos run at the same time.
///
/// Every line gets the repo as prefix, so interleaved output stays readable.
/// Status printers redraw their line with cursor escapes; in parallel output
/// that would erase the line of another repo, so the escapes are removed and
/// the »running« line of a status is dropped. The full, unprefixed log goes
/// to [file] as well.
class LaneLog {
  /// Constructor
  LaneLog({required this.prefix, required this.ggLog, this.file});

  /// A lane that keeps its lines in [lines].
  factory LaneLog.example({String? prefix, List<String>? lines}) =>
      LaneLog(prefix: prefix ?? 'ggsuite/gg_json', ggLog: (lines ?? []).add);

  // ...........................................................................
  /// Shown in front of every line.
  final String prefix;

  /// Receives the prefixed lines.
  final GgLog ggLog;

  /// Receives every line without prefix, if given.
  final File? file;

  // ...........................................................................
  /// Logs [message], line by line.
  void call(String message) {
    for (final line in clean(message).split('\n')) {
      if (line.trim().isEmpty || line.startsWith(_running)) continue;
      ggLog('${darkGray('[$prefix]')} $line');
      file?.writeAsStringSync('$line\n', mode: FileMode.append);
    }
  }

  // ...........................................................................
  /// Removes the cursor movements and line erasures of [message].
  static String clean(String message) =>
      message.replaceAll(_cursorEscape, '').replaceAll('\r', '');

  static final _cursorEscape = RegExp(r'\x1B\[\d*[ABCDEFGHJK]');
  static const _running = '⌛️';
}
