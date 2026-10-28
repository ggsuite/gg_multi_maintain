# gg_multi_maintain

English | [Deutsch](README.de.md)

[![CI](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml/badge.svg)](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml)
[![pub package](https://img.shields.io/pub/v/gg_multi_maintain.svg)](https://pub.dev/packages/gg_multi_maintain)

Runs maintenance tasks like SDK, DNA and dependency upgrades in all ocean repos in parallel and publishes every changed repo.

## Motivation

A gg workspace holds a hundred repos in its ocean. Raising the Dart SDK,
pulling in a new DNA layer or upgrading the dependencies used to mean a
ticket per repo, or one huge ticket whose dependency hull dragged every
repo in. `gg do maintain` does such routine work for the whole ocean in
one call:

- every repo gets its own fresh clone and branch, the ocean stays as it is
- the repos run in parallel, but a repo waits for the repos it depends
  on, so an upgrade sees the versions the same run just released
- every changed repo is committed and published on its own with
  `gg one do publish`, with all checks and tests of `gg one do commit`
- a failing repo only stops the repos that depend on it

## Installation

`gg do maintain` comes with gg:

```bash
dart pub global activate gg
```

## Usage

Run it at the root of a gg workspace and choose at least one task:

```bash
gg do maintain --upgrade-sdk                 # Dart SDK and Node constraints
gg do maintain --upgrade-dna                 # the DNA layers, then regenerate
gg do maintain --upgrade-deps                # compatible dependency upgrades
gg do maintain --upgrade-deps --major        # also across major versions
gg do maintain --all --org ggsuite --dry-run # see what would change
```

| Option | Meaning |
| --- | --- |
| `--upgrade-sdk` | Raises `environment: sdk:` to the installed Dart and `engines.node` to the installed Node |
| `--upgrade-deps` | Upgrades the dependencies to the newest compatible versions |
| `--major` | With `--upgrade-deps`: allows major version jumps |
| `--upgrade-dna` | Upgrades the DNA layers and the helix engine, then regenerates the DNA |
| `--all` | All tasks above |
| `-j`, `--jobs` | How many repos run at the same time, default 4 |
| `--org`, `--repo` | Limit the run, e.g. `--org tssuite` or `--repo 'gg_*'` |
| `--version-increment` | `patch`, `minor` or `major` for every repo |
| `--no-pana` | Skip pana before publishing Dart packages |
| `-n`, `--dry-run` | Apply the tasks and report the changes, without commit and publish |

The example prints the help of the command:

```dart
import 'package:args/command_runner.dart' show CommandRunner;
import 'package:gg_multi_maintain/gg_multi_maintain.dart';

Future<void> main() async {
  final runner = CommandRunner<void>('gg', 'Maintains the ocean.')
    ..addCommand(DoMaintain(ggLog: print));
  await runner.run(['help', 'maintain']);
}
```

At the end, the command prints a summary like this:

```text
Published (2):
  ggsuite/gg_hash: 3.1.5
  ggsuite/gg_json: 2.4.1
Unchanged (1):
  ggsuite/gg_log
Skipped (1):
  ggsuite/testproject_gg_1: a test project
```

## Limitations

- Test projects, private packages and repos without a remote are
  skipped. A package that was never published is skipped too, because its
  first version is published by hand.
- npm publishes may ask for a one-time password, so they run one at a
  time. pnpm's minimum release age can hold back a version that the same
  run has just published.
- Only lock files or gg's state in `.gg/` changed? Then the repo counts as
  unchanged and is not published.

## How it works

Each run gets a folder `<workspace>/.maintain/<run id>/<org>/<repo>`.
The pipeline of a repo is: clone, skip it if it was never published,
create the branch `maintain_<run id>`, install, run the tasks, detect
the changes, `gg one do commit`, `gg one do publish`, delete the clone.
The version increment is `minor` when a regular dependency jumps across
its old constraint, otherwise `patch`. A failed clone stays in the run
folder with its log.

## Status

Before 1.0 — the options may change between minor versions.

## Contributing

See the [Develop Guide](doc/guides/develop-guide.md).

## License

MIT — see [LICENSE](LICENSE).
