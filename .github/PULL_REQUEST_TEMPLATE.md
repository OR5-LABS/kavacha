## Summary

<!-- What does this PR change, and why? -->

## Related issue

<!-- Closes #___, or "N/A" -->

## Type of change

- [ ] Bug fix
- [ ] New feature / configuration
- [ ] Documentation
- [ ] Refactor / cleanup (no functional change)
- [ ] Build / tooling / CI

## Verification checklist

Check the ones you ran locally. If something doesn't apply to this change
(e.g. a docs-only PR), leave it unchecked and say why below.

- [ ] `./build.sh` — compile + smoke test
- [ ] `./build.sh cosim` — golden-model co-simulation
- [ ] `./build.sh rvfi` — RVFI formal self-check
- [ ] `./build.sh debug` — JTAG / Debug-Module self-check
- [ ] `./build.sh pmp` — SECURE config PMP test (if touching privilege/memory protection)
- [ ] `./build.sh ecc` — register-file ECC test (if touching the register file)

**Notes on what was skipped and why (if applicable):**

## Checklist

- [ ] Commits are signed off (`git commit -s`) per the DCO in CONTRIBUTING.md
- [ ] Code follows the style conventions in CONTRIBUTING.md
- [ ] I added or updated a test that would fail without this change
- [ ] I updated relevant docs (README / docs/) if behavior changed
- [ ] This PR is scoped to one change, not several unrelated ones

## Anything else reviewers should know?

<!-- Design tradeoffs, open questions, follow-up work you're intentionally leaving out -->