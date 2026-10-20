## Submission

Update from mcplite 0.1.0 to 0.2.0.

## Local checks

Checked on Ubuntu 24.04.5 LTS, x86_64-pc-linux-gnu, with R 4.6.1.

- `devtools::test()`: 1,969 passed; 0 failures, warnings, or skips.
- Final `devtools::check(document = FALSE, cran = TRUE, manual = TRUE)`
  with an external check directory: 0 errors, 0 warnings, 0 notes.
  PDF and HTML manual checks passed.
- Live rairai smoke tests passed after reinstalling the consumer, including
  both CRAN lookup tools and recovery after an invalid package-root request.

## Website and CI checks

- The updated website is deployed; `urlchecker::url_check()` passes all URLs.
- GitHub Actions passed on macOS and Windows with R release, and Ubuntu with
  R-devel, for candidate commit cc334aa on 2026-10-20.
- Air formatting and pkgdown build/deployment passed.
- Source archive excludes internal records and agent configuration files.

## Compatibility

Previously installed consumers that store tool objects constructed by mcplite
0.1.0 may require reinstallation after upgrading. The maintainer chose to move
rairai's tool construction to server startup in a separate follow-up rather
than add old-object compatibility handling to mcplite. The reinstalled rairai
consumer passes the live smoke tests; the persistent construction change is
not part of this release.
