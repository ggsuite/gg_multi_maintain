<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Install npm dependencies without audit and fund

## Motivation

- Every maintained TypeScript repo gets its dependencies installed before
  the tasks run
- `npm install` also asks the registry for a security audit and collects
  funding notes; nothing in a maintenance run reads either
- These requests make the install slow and unpredictable: an install
  without any dependency took 11.6 s once, 0.8 s afterwards
- The test of the install hit its 30-second limit on a busy machine

## Strategy

- Skip what the run does not need, keep the install itself unchanged
- Give the test of the real install the time a busy machine needs

## Implementation

- npm runs as `npm install --no-audit --no-fund`
- pnpm and yarn keep a plain `install`: they audit nothing on install
- `node_modules` and the lock file come out the same as before
- The test `installs the npm dependencies of a TypeScript repo` may take
  two minutes instead of 30 seconds

## Open Points

- An audit is still possible by hand with `npm audit`
