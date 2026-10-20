## Submission

Update from mcplite 0.1.0 to 0.2.0.

## Local checks

Checked on Ubuntu 24.04.5 LTS, x86_64-pc-linux-gnu, with R 4.6.1.

- `devtools::test()`: 1,969 passed; 0 failures, warnings, or skips.
- `devtools::check(document = FALSE, check_dir = tempdir(), cran = TRUE)`:
  0 errors, 0 warnings, 0 notes (`--as-cran --no-manual`).
- Live rairai smoke tests passed after reinstalling the consumer, including
  both CRAN lookup tools and recovery after an invalid package-root request.

## Pending before submission

- Deploy the updated website and rerun `urlchecker::url_check()`: the new
  writing-tools and returning-results article URLs currently return 404.
- Review CI results for this release candidate after pushing. Results from the
  previous release are not validation of this candidate.

## Compatibility

Previously installed consumers that store tool objects constructed by mcplite
0.1.0 may require reinstallation after upgrading. The maintainer chose to move
rairai's tool construction to server startup in a separate follow-up rather
than add old-object compatibility handling to mcplite. The reinstalled rairai
consumer passes the live smoke tests; the persistent construction change is
not part of this release.
