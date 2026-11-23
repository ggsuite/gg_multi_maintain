# Changelog

## Unreleased

### Removed

- Maintain the repos in a normal ticket, add --continue

Run gg do upgrade ocean first, then create the ticket maintain_<run id>
Add all selected repos with gg do add --no-localize
Keep the run state in <ticket>/.gg/publish_state.json
--continue [-i <ticket>] goes on with the repos that are not done
Remove the ticket when green, keep it with report.txt otherwise
Maintain test projects and private packages too, never publish
--dry-run clones into a temp folder, drop the .maintain folder

## 0.2.1 - 2026-11-20

### Added

- Add the blog post on npm install without audit

### Changed

- Install npm dependencies without audit and fund

## 0.2.0 - 2026-11-15

### Added

- Add the blog post on merging into main

### Changed

- Describe the merge in the library docs

### Removed

- Merge maintained repos into main instead of publishing

## 0.1.1 - 2026-11-15

### Added

- Add the blog post on gg dna upgrade

### Changed

- Regenerate the DNA with gg dna upgrade

## 0.1.0 - 2026-11-15

### Added

- Add --nightly and a report of a failed run
- Add the blog post about the nightly build
- Add the German blog post about the nightly build

## 0.0.2 - 2026-10-28

### Added

- Add the initial version
- Add gg do maintain: run SDK, DNA and dependency upgrades in all ocean repos in parallel and publish every changed repo
