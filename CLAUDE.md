# gg_multi_maintain

`gg do maintain`: routine maintenance for every repo of the ocean in one
call, each changed repo merged into main on its own — nothing is published
to a registry. Part of the gg_multi family; gg_multi registers the command
under `gg do`.

## Concept

- **A run is a normal ticket.** `TicketRepoHost` (`RepoHost`) runs
  `gg do upgrade ocean` (a failure aborts the run), creates the ticket
  `maintain_<run id>` and adds every selected repo in one
  `gg do add --no-localize --no-transitive` — all through the
  gg_multi_workspace commands, in-process. The ticket id is also the branch.
  `do add` leaves the files it maintains (`.gitattributes`, …) uncommitted
  without localizing; `RepoHost.restore` resets the fresh checkouts, so they
  never count as a change. `--dry-run` uses `CloneRepoHost` instead: temp
  clones, no ocean sync, no ticket, no state.
- **The state makes the run resumable.** `MaintainState` lives below the key
  `maintain` of `<ticket>/.gg/publish_state.json` (other keys stay): options,
  repos with their checkout, the base commit of every repo (recorded once,
  before the first task) and the results, saved after every repo.
  `Maintainer.resume` (`--continue [-i <ticket>]`) maintains every repo that
  is not merged, unchanged or skipped, in the existing checkout, and resumes
  an unfinished merge (`DoPublish(resume: true)`). Changes are measured
  against the base, so commits of the earlier run or of the developer count.
- **A green run removes its ticket** (`gg do rm ticket
  --no-delete-remote-branch`, the merge deleted the branches). A run with
  problems keeps it with `report.txt` and the logs of the failed repos
  (`.gg/maintain_logs/<org>/<repo>.log`) and names the `--continue` call.
- **Parallel, but in dependency order.** `DagScheduler` starts a repo as soon
  as all repos it depends on (dev dependencies included, so DNA layers come
  first) are merged or unchanged, up to `--jobs` at a time. A failure blocks
  its dependents only. There are no waves: a fast branch of the graph never
  waits for a slow one.
- **gg does the merge.** Commit and merge are `gg one do commit` and
  `gg one do publish --merge-only` (`DoCommit`, `DoPublish`) called
  in-process with every answer given (`askBeforePublishing: false`,
  `upgrade: false`) — no prompt may appear, there is no terminal per repo.
  Nothing is uploaded, versioned or tagged.
- **Every repo with a remote takes part**, test projects and private
  packages too; only repos without a remote are skipped.
- **A task flag is required** for a new run. `--upgrade-sdk`,
  `--upgrade-deps [--major]`, `--upgrade-dna`, `--all` or `--nightly`
  (= `--upgrade-deps --major`, the run a computer of its own starts every
  night; combinable with the other task flags). New tasks are a
  `MaintainTask` value plus a `RepoTask` in `RepoMaintainer._defaultTasks`;
  they only change files, the pipeline detects and merges the changes.
- **Unchanged is decided by git.** Lock files and `.gg/` do not count.

## Layout

- `commands/do_maintain.dart` — flags, validation, workspace lookup, the
  ticket `--continue` goes on with
- `backend/maintainer.dart` — host → selection → state → dependency order →
  scheduler → report, removes or keeps the ticket
- `backend/repo_host.dart` — `TicketRepoHost`, `CloneRepoHost`
- `backend/maintain_state.dart` — the state of a run
- `backend/repo_maintainer.dart` — the pipeline of one repo
- `backend/repo_selection.dart` — `--org`/`--repo`, skips repos without
  remote
- `tasks/` — `UpgradeSdk`, `UpgradeDeps`, `UpgradeDna`

## Follow-ups

- Show the lanes with `gg_parallel_log` once it is published (`LaneLog` is
  the interim prefixed log).

<!-- helix:claude_md:start -->

@.claude/CLAUDE_dna_gg.md

<!-- helix:claude_md:end -->
