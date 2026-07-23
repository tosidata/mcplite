## Submission

This is the first submission of mcplite.

## Final local environment

- Ubuntu 24.04.4 LTS, x86_64-pc-linux-gnu
- R 4.6.1 (2026-06-24)

## Direct test results

- 672 passed, 0 failed, 0 warnings, and 1 expected skip outside check mode.

## Final R CMD check results

A fresh source tarball was checked with `R CMD check --as-cran --timings`.

- 0 errors, 0 warnings, and 1 note
- Examples: OK
- PDF manual: OK
- Source archive: no `.eca` or `AGENTS.md` files

## Notes

1. Local HTML validation was skipped because the system `tidy` command was
   unavailable. This is a limitation of the local validation environment.
2. URL validation of the GitHub Actions badge is deferred while the new
   repository remains private; unauthenticated requests return HTTP 404.

## GitHub Actions matrix validation

On 2026-07-23, the clean repository snapshot passed the GitHub Actions matrix:

- macOS latest with R release: passed
- Windows latest with R release: passed
- Ubuntu latest with R-devel: passed
- Air formatting and lint checks: passed

## External validation disposition

On 2026-07-23, the maintainer accepted the completed local and GitHub Actions
matrix checks as sufficient for this preparation round. Win-builder and R-hub
will not be used for this round.

## Pending before submission

- Make the GitHub repository public, then add accessible `URL` and
  `BugReports` fields.
- Rerun URL validation after adding `URL` and `BugReports`.
- Perform the final case-insensitive package-name availability check against
  current CRAN, the CRAN Archive, and current Bioconductor.
