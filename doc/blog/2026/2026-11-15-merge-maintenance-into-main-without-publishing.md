<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Merge maintained repos into main instead of publishing

## Motivation

- Maintenance should keep the main branches current, not release
- A release belongs to a normal ticket and its review

## Strategy

- Keep the pipeline: clone, tasks, `gg one do commit` with all checks
- Replace the release step by `gg one do publish --merge-only`: no new
  version, no `CHANGELOG.md` release heading, no upload, no tag
- Keep the dependency order: a repo still waits for the repos it depends
  on, a failed repo still blocks its dependents

## Implementation

- `PublishStep` becomes `MergeStep`; the outcome `published` becomes
  `merged`, reported with the changed files
- `--version-increment` and `--pana` are gone, and with them
  `VersionIncrement`
- npm repos no longer run one at a time: nothing asks for a one-time
  password any more
- README, README.de and index.jsonc describe the merge; the nightly
  computer only needs `gh auth login`

## Open Points

- The changes wait below `## Unreleased` until a ticket publishes the repo
