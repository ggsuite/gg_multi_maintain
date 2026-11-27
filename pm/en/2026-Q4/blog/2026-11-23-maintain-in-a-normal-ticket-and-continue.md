<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Maintain in a normal ticket and continue after a failure

## Motivation

- A run used to clone every repo into `<workspace>/.maintain/<run id>` and
  delete the clones again. A failed repo left a clone nobody knew how to
  continue with: the developer had to fix it in a new ticket and wait for
  the next run
- The run should work where every other gg work happens — in a ticket —
  and go on from where it stopped once the failed repos are fixed

## Strategy

- Sync the ocean first with `gg do upgrade ocean`; a failure ends the run
- Create a normal ticket `maintain_<run id>` and add all selected repos in
  one `gg do add --no-localize`; the ticket id is also the branch
- Keep the run state in the ticket and save it after every repo
- `gg do maintain --continue` maintains what is not done yet, in the
  checkouts of the ticket
- Remove the ticket when everything went well, keep it with `report.txt`
  otherwise; the `.maintain` folder is gone

## The ticket

- `RepoHost` provides the checkouts of a run: `TicketRepoHost` runs
  `UpdateOceanCommand`, `TicketCommand`, `AddCommand` and
  `RemoveTicketCommand` of gg_multi_workspace in-process
- Without localizing, `gg do add` leaves the files it maintains, like
  `.gitattributes`, uncommitted. The fresh checkouts are reset, so they
  never count as a change
- A checkout is found by its remote, in one pass over the ticket
- `--dry-run` uses `CloneRepoHost`: temporary clones, cloned `--jobs` at a
  time, no ocean sync, no ticket

## Continue

- `MaintainState` lives below the key `maintain` of
  `<ticket>/.gg/publish_state.json`, the run state file of every ticket;
  its other keys stay
- It holds the options, the repos, their dependencies, the commit every
  repo started from and the results
- `--continue [-i <ticket>]` takes the ticket of `-i`, the ticket it runs
  in, or the latest `maintain_*` ticket, and refuses the options of a new
  run
- Repos that are merged, unchanged or skipped are not touched again;
  missing checkouts are added again, an unfinished merge is resumed
- Changes are measured against the start commit, so commits of the earlier
  run and of the developer count

## Every repo with a remote

- Maintenance merges and publishes nothing to a registry, so test
  projects and private packages are maintained too
- Only repos without a remote are skipped
- A checkout that is not on the run's branch fails before anything is
  committed

## Open Points

- `gg do publish` in a maintenance ticket would rewrite
  `publish_state.json` without the `maintain` key
- Two repos of the same name from different organizations cannot share a
  ticket; the second one fails as missing
