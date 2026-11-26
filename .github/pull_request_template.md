<!-- Every pull request is for an issue: open one first if there is none, and end
the title with its number, such as "Fix the hem allowance (#123)". The Linked
issue check fails until the title names an issue of this repository. -->

## What this changes and why

<!-- Say which issue it is for: "For #123", or "Fixes #123" when it closes it -->

## Checklist

- [ ] It is for an issue, whose number ends the title
- [ ] `./opensloper-make.sh format`, `./opensloper-make.sh check`, `./opensloper-make.sh test` and `./opensloper-make.sh build` pass locally (Lazarus 4.8, FPC 3.2.2)
- [ ] New or changed behaviour has tests; a bug fix has a test that fails without it
- [ ] User-visible text is in `resourcestring` sections
- [ ] User changes go through undoable `TCommand`s
- [ ] The design document is updated, if a design decision changed
- [ ] Nothing in `src/packages/` is changed
- [ ] I agree that my contribution is licensed under GPLv3 or later (see `CONTRIBUTING.md`)
