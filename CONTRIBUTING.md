# Contributing to Kavacha

Thanks for your interest in Kavacha. This project is early — v1 is a
starting point, not a finished design — and there's real room to shape
where it goes next, whether that's RTL, verification, tooling, or docs.

This guide covers how to get set up, what we expect from a pull request,
and how review works.

## Before you start

- Bug fixes and small, well-scoped improvements: open a PR directly.
- New features, new configurations, or anything that touches the ISA
  surface or privilege/security model: please open an issue first to
  discuss the approach before writing code. This saves you from
  rework and helps us keep the core's scope coherent.
- For anything else, feel free to open a
  [issue](https://github.com/OR5-LABS/kavacha/issues) — asking is
  always welcome.

## Getting set up

You'll need:

- Icarus Verilog 12+ (`iverilog` / `vvp`)
- Python 3.10+
- *(optional)* a RISC-V GCC toolchain, if you're changing the assembly
  test programs
- *(optional)* Vivado, if you're touching the FPGA flows

```bash
git clone https://github.com/OR5-LABS/kavacha
cd kavacha
./build.sh          # compile + self-checking smoke test
```

## Before opening a pull request

Every PR that touches `rtl/` should pass the full local verification
suite, not just the smoke test:

```bash
./build.sh          # compile + self-checking smoke test
./build.sh cosim    # co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh pmp      # SECURE config: User mode + PMP test program
./build.sh ecc      # register-file SECDED ECC unit test
```

If your change is scoped to something that doesn't touch a particular
subsystem (e.g. a docs fix, or a change to `fpga/` only), the relevant
subset is fine — but please say in the PR description which checks you
ran and which you skipped, and why.

If you're adding a feature, please add a test that would fail without
your change. A PR that only adds RTL without a corresponding test is
unlikely to be merged as-is.

## Code style

- SystemVerilog, 2-space indentation, no tabs.
- One module per file; file name matches the module name.
- `snake_case` for modules, signals, and parameters; `SCREAMING_SNAKE_CASE`
  for `parameter` / `localparam` constants.
- Explicit port directions and widths on every port declaration — avoid
  implicit widths.
- Synchronous reset, one clock domain unless there's a specific reason
  otherwise (and if so, explain it in the PR description).
- No latches. If a `case` statement doesn't cover every value, add a
  `default` branch.
- Comment *why*, not *what* — the code should already say what it does.
- Keep leaf-cell modules under `rtl/common/` self-contained and reusable;
  avoid reaching into `kavacha_core.sv` internals from elsewhere.

If existing code in the file you're editing does something differently,
match the existing convention in that file rather than mixing styles.

## Commit messages and PR description

- Commit messages: short imperative summary line (`Fix misaligned store
  in LOAD state`), with a blank line and more detail below if needed.
- PR description should cover: what changed, why, and which of the
  `build.sh` checks above you ran.
- Keep PRs focused. Large, multi-purpose PRs are harder to review and
  more likely to sit — if your change is naturally two things, consider
  two PRs.

## Sign-off (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/)
rather than a CLA. Sign off each commit to confirm you have the right to
submit the contribution under the project's license:

```bash
git commit -s -m "Your commit message"
```

This adds a `Signed-off-by:` line using your Git user name and email.

## Review process

A maintainer will review your PR. Expect an initial response within about a week.
We may ask for changes; that's normal and not a sign the contribution
isn't wanted.

## Reporting bugs

Please use the bug report issue template and include:

- What you expected vs. what happened
- Which `build.sh` target you were running (if applicable)
- Your simulator/toolchain versions
- A minimal way to reproduce it, if you have one

## Security issues

Please don't open a public issue for a potential security vulnerability
(e.g. a PMP bypass or debug-access issue). See `SECURITY.md` for how to
report it privately.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you're expected to uphold it.