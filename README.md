# gg_multi_maintain

English | [Deutsch](README.de.md)

[![CI](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml/badge.svg)](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml)
[![pub package](https://img.shields.io/pub/v/gg_multi_maintain.svg)](https://pub.dev/packages/gg_multi_maintain)

Runs maintenance tasks like SDK, DNA and dependency upgrades in all ocean repos in parallel and merges every changed repo into its main branch, without publishing.

## Motivation

A gg workspace holds a hundred repos in its ocean. Raising the Dart SDK,
pulling in a new DNA layer or upgrading the dependencies used to mean a
ticket per repo, or one huge ticket whose dependency hull dragged every
repo in. `gg do maintain` does such routine work for the whole ocean in
one call:

- the run syncs the ocean with `gg do upgrade ocean`, creates a normal
  ticket `maintain_<run id>` and adds every repo to it, without
  localizing the references between them
- the repos run in parallel, but a repo waits for the repos it depends
  on, so no repo is maintained on top of a broken one
- every changed repo is committed with all checks and tests of
  `gg one do commit` and merged into its main branch with
  `gg one do publish --merge-only`
- nothing is released: no new version, no upload, no tag. The changes
  wait below `## Unreleased` in `CHANGELOG.md`. Everything that is
  published anywhere goes through a normal ticket and its review
- a failing repo only stops the repos that depend on it
- a run that went well removes its ticket. A run with problems keeps it:
  fix the failed repos there and go on with `gg do maintain --continue`

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
gg do maintain --nightly                     # the nightly build
gg do maintain --upgrade-dna --run migrate.dart # a script, then the DNA
gg do maintain --all --org ggsuite --dry-run # see what would change
gg do maintain --continue                    # go on after a failed run
```

| Option | Meaning |
| --- | --- |
| `--upgrade-sdk` | Raises `environment: sdk:` to the installed Dart and `engines.node` to the installed Node |
| `--upgrade-deps` | Upgrades the dependencies to the newest compatible versions |
| `--major` | With `--upgrade-deps`: allows major version jumps |
| `--upgrade-dna` | Upgrades the DNA layers and the helix engine, then runs `gg dna upgrade`: places the newest DNA check and regenerates the DNA |
| `--all` | All tasks above |
| `--run <script>` | Runs a script in the root of every repo, after the SDK and the dependencies and before the DNA, so the DNA regenerates on top of it. `.dart` runs with `dart run`, `.js`/`.mjs` with `node`, `.sh` with `bash`, `.ps1` with `pwsh`, anything else as it is. A script that exits with a code other than 0 fails the repo. Alone or together with the task flags; `--all` does not include it |
| `--nightly` | The nightly build: `--upgrade-deps --major`, see below |
| `-j`, `--jobs` | How many repos run at the same time, default 4 |
| `--org`, `--repo` | Limit the run, e.g. `--org tssuite` or `--repo 'gg_*'` |
| `-n`, `--dry-run` | Apply the tasks in temporary clones and report the changes: no ticket, no commit, no merge |
| `--continue` | Go on with a run that had problems, in its ticket; takes the options of that run |
| `-i`, `--ticket` | With `--continue`: the ticket of the run. Default: the ticket the command runs in, else the latest `maintain_*` ticket |

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
Merged (2):
  ggsuite/gg_hash: pubspec.yaml
  ggsuite/gg_json: pubspec.yaml, 1 other file
Unchanged (1):
  ggsuite/gg_log
Skipped (1):
  ggsuite/testproject_gg_1: a test project
```

## Nightly build

Commit, push and publish of a ticket upgrade no dependency. New versions,
major versions included, reach the main branches through one run every
night:

```bash
gg do maintain --nightly
```

It raises the dependencies of every repo across major versions and
merges every changed repo into main without a review — it changes
versions, no code. It releases nothing; the next ticket that publishes a
repo releases its upgrades too. A repo whose checks or tests fail after the
upgrade is not merged, and nothing is merged on top of it: the repos depending on
it are blocked. The run then exits with an error, keeps its ticket and writes
`<workspace>/maintain_<run id>/report.txt`: which repo failed, in which
step, why, and where its checkout and log are. Fix the repo in the
ticket and run `gg do maintain --continue`, or leave it to the next
night, which starts over in a ticket of its own.

### Set up the computer of the nightly build

The nightly build runs on a computer of its own, not on a developer's
machine and not on GitHub:

1. Install Dart, Flutter (for Flutter repos), Node with pnpm, git and the
   GitHub CLI, then gg: `dart pub global activate gg`
2. Sign in once, with an account that may push to `main` through pull
   requests: `gh auth login`. No registry login is needed, the run
   uploads nothing
3. Create a workspace with the ocean of the organizations, e.g.
   `C:\nightly\.ocean`, as on a developer machine. `gg do upgrade ocean`
   brings in the repos created since
4. Schedule the run at night, from the workspace root. On Windows:

   ```bash
   schtasks /create /tn gg-nightly /sc daily /st 02:00 /tr "cmd /c cd /d C:\nightly && gg do maintain --nightly > nightly.log 2>&1"
   ```

   On Linux or macOS, as a line of the crontab:

   ```bash
   0 2 * * * cd ~/nightly && gg do maintain --nightly > nightly.log 2>&1
   ```

5. Read `nightly.log` and, after a failed night, the `report.txt` it
   names

## Limitations

- Repos without a remote are skipped: there is no main branch to merge
  into. Test projects and private packages are maintained like every other
  repo — the run publishes nothing anyway.
- `gg do upgrade ocean` stops the run when an ocean repo carries local
  work; commit, push or drop it first.
- Only lock files or gg's state in `.gg/` changed? Then the repo counts as
  unchanged and is not merged.

## How it works

A run creates the ticket `<workspace>/maintain_<run id>` with
`gg do create ticket` and adds every selected repo with
`gg do add --no-localize`; each repo sits on the branch
`maintain_<run id>`. The pipeline of a repo is: install, run the tasks,
detect the changes since the commit the run started from,
`gg one do commit`, `gg one do publish --merge-only`. The state of the run
— its options and how every repo ended — is kept below the key
`maintain` of `<ticket>/.gg/publish_state.json` and saved after every
repo; `--continue` reads it and maintains every repo that is neither
merged nor unchanged yet, in the checkout the ticket holds. The log of a
failed repo is in `<ticket>/.gg/maintain_logs/<org>/<repo>.log`.

## Status

Before 1.0 — the options may change between minor versions.

## Contributing

See the [Develop Guide](doc/guides/develop-guide.md).

## License

MIT — see [LICENSE](LICENSE).
