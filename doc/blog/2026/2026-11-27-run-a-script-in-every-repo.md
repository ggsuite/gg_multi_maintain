<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Run a script in every repo

## Motivation

- Some maintenance is no upgrade: a migration moves files, renames a
  config key or rewrites links, and it has to happen in every repo
- `gg do maintain` already runs in every repo in parallel, in dependency
  order, and commits and merges what changed; only the tasks were fixed

## Strategy

- Add `--run <script>`: a script that runs in the root of every repo
- Run it after the SDK and the dependencies and before the DNA, so the DNA
  regenerates on top of what the script changed
- Keep it beside the task flags: it goes alone or together with them, and
  `--all` does not include it

## --run

- The interpreter follows the extension: `.dart` with `dart run`, `.js`
  and `.mjs` with `node`, `.sh` with `bash`, `.ps1` with `pwsh`; any other
  file runs as it is
- The path is made absolute when the run starts and must exist
- A script that exits with a code other than 0 fails the repo in the step
  `run <script name>`; its output goes to the log of the repo
- The commit and merge message names it, e.g. »Upgrade the DNA and run
  migrate.dart«, or »Run migrate.dart« alone
- `--continue` keeps the script, it is part of the saved options
- The script runs once per repo: `--continue` skips it in a repo that
  changed since the start; a script that is gone says so

## Tests

- The options: script in the JSON round trip, the messages with and without
  tasks
- The command: `--run` alone, with a task flag, with a missing file
- The pipeline: the order SDK, script, DNA; the script last without the DNA;
  a failing script; a real Dart script
- `RunScript`: the interpreter per extension, a script that writes a file
  and logs, a script that fails
