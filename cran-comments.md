## Submission

This is the first submission of mcplite, current as of July 23, 2026.

## Final local environment

- Ubuntu 24.04.4 LTS, x86_64-pc-linux-gnu
- R 4.6.1 (2026-06-24)

## Direct test results

- 672 passed, 0 failed, 0 warnings, and 1 expected skip outside check mode.

## Final R CMD check results

A fresh source tarball was checked with `R CMD check --as-cran --timings`.

- 0 errors, 0 warnings, 1 note
- Notes: expected incoming-feasibility note for the maintainer identity and `New submission`
- Examples: OK
- PDF manual: OK
- Source archive: no `.eca` or `AGENTS.md` files

## Release documentation validation

- The public GitHub repository and GitHub Pages site are live.
- `urlchecker::url_check()` passed all 5 URLs.
- The final package-name audit found no collision.

## GitHub Actions matrix validation

On 2026-07-23, the clean repository snapshot passed the GitHub Actions matrix:

- macOS latest with R release: passed
- Windows latest with R release: passed
- Ubuntu latest with R-devel: passed
- Air formatting and lint checks: passed

## External validation disposition

Win-builder and R-hub were not used. The maintainer accepted the local and
GitHub Actions matrix validation as sufficient for this first submission.
