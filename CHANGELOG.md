## Unreleased

* Correctly handle and drain 5xx download responses, including `Retry-After`.
* Add safe Last-Modified resume and reject unvalidated partial-file resumes.
* Add optional small-file resume-metadata suppression and coalesced progress.
* Report per-attempt progress, retry-wide bytes/timing, response headers and
  actual native-to-dart:io fallback selection.
* Make retry backoff cancellable.

## [0.0.1] - Initialize package

* Initialize package
