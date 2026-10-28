# gg_multi_maintain

`gg do maintain`: routine maintenance for every repo of the ocean in one
call, each repo released on its own. Part of the gg_multi family; gg_multi
registers the command under `gg do`.

## Concept

- **The ocean is read, never written.** Every repo is cloned fresh to
  `<workspace>/.maintain/<run id>/<org>/<repo>` and maintained on the branch
  `maintain_<run id>`. Only failed clones and their logs stay.
- **Parallel, but in dependency order.** `DagScheduler` starts a repo as soon
  as all repos it depends on (dev dependencies included, so DNA layers come
  first) are published or unchanged, up to `--jobs` at a time. A failure
  blocks its dependents only. There are no waves: a fast branch of the graph
  never waits for a slow one.
- **gg does the release.** Commit and publish are `gg one do commit` and
  `gg one do publish` (`DoCommit`, `DoPublish`) called in-process with every
  answer given (`askBeforePublishing: false`, `upgrade: false`, version
  increment, merge message) — no prompt may appear, there is no terminal per
  repo. npm publishes run one at a time because of OTP prompts.
- **A task flag is required.** `--upgrade-sdk`, `--upgrade-deps [--major]`,
  `--upgrade-dna` or `--all`. New tasks are a `MaintainTask` value plus a
  `RepoTask` in `RepoMaintainer._defaultTasks`; they only change files, the
  pipeline detects and releases the changes.
- **Unchanged is decided by git.** Lock files and `.gg/` do not count. The
  version increment is `minor` when a regular dependency leaves its old
  constraint, otherwise `patch`; `--version-increment` overrides it.

## Layout

- `commands/do_maintain.dart` — flags, validation, workspace lookup
- `backend/maintainer.dart` — selection → dependency order → scheduler →
  report, cleans the run folder
- `backend/repo_maintainer.dart` — the pipeline of one repo
- `backend/repo_selection.dart` — `--org`/`--repo`, skips test projects,
  private packages and repos without remote
- `tasks/` — `UpgradeSdk`, `UpgradeDeps`, `UpgradeDna`, `VersionIncrement`

## Follow-ups

- Show the lanes with `gg_parallel_log` once it is published (`LaneLog` is
  the interim prefixed log).

<!-- helix:claude_md:start -->

@.claude/CLAUDE_dna_gg.md

<!-- helix:claude_md:end -->
