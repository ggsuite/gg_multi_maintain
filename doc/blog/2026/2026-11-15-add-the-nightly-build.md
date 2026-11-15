<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Add the nightly build

## Motivation

- `gg do maintain` upgrades the SDK, the DNA or the dependencies of every
  ocean repo in parallel and publishes each changed repo on its own
- Packages and apps stay current only if somebody runs it — major versions
  included, and every day
- That run should happen on a computer of its own, every night, without
  anybody watching: it changes versions, no code, so it needs no review
- When a major version breaks a repo, nothing may be published on top of
  it, and the developer has to learn which repo broke and why

## Strategy

- Add `--nightly` as the one flag a schedule starts
- Keep the pipeline: a failed repo already blocks the repos that depend on
  it and keeps its clone and log
- Leave a report in the run folder, because nobody reads the output of a
  scheduled run
- Describe how to set up the computer

## --nightly

- `--nightly` is `--upgrade-deps --major`: every dependency, across major
  versions
- It goes with the other task flags, e.g. `--nightly --upgrade-dna`
- The usage line and the help name it; `--major` without
  `--upgrade-deps` is still refused

## The report

- When a repo failed or was blocked, `Maintainer.run` writes
  `<workspace>/.maintain/<run id>/report.txt` and logs its path
- It holds the run id and the summary without colors: which repo failed,
  in which step, the first line of the error, and where its clone and log
  are; the blocked repos with the repo they wait for
- `MaintainReport.lines(colored: false)` and `MaintainReport.text(runId:)`
  produce it
- A run without problems leaves no report, and its run folder is removed as
  before

## The computer of the nightly build

- The README (English and German) lists the steps: install the tools and
  gg, sign in to GitHub and pub.dev, an npm token that publishes without a
  one-time password, a workspace with the ocean, and the schedule —
  `schtasks` on Windows, a crontab line on Linux and macOS
- `gg do upgrade ocean` brings in repos created since
- `index.jsonc` was added: the repo had none

## Tests

- `--nightly` alone and together with `--upgrade-dna`
- The report of a failed run: run id, failed and blocked repos, no color
  codes, its path in the log; no report when nothing failed
- `lines(colored: false)` and `text(runId:)` of `MaintainReport`

## Open Points

- The computer is not set up yet, and who looks after it is open
- A failed night only leaves the report and the exit code; a mail or an
  issue may follow
