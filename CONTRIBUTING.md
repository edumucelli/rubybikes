# Contributing

Use Ruby 3.4 for development; runtime tests cover Ruby 3.1–3.4 and 4.0.
Run `bin/setup`, then `bundle exec rake test build`. Quality checks use
`BUNDLE_GEMFILE=gemfiles/quality.gemfile bundle exec rake lint typecheck` after
installing that bundle. `docker build -f Dockerfile.test -t rubybikes-test .`
and `docker run --rm --network none rubybikes-test` reproduce the offline checks.

For a provider change, add an anonymized response fixture and explicit expected
station/vehicle fields. Assert HTTP method, body, query parameters, and relevant
headers. Test geography, authentication, unknown counts, and failure behavior
where applicable. Preserve network tags and identity hashes. A client is only
covered after it produces a nonempty snapshot in an offline test; construction
alone is insufficient. Never introduce skips or hide a shipped source file to
meet coverage requirements.

The catalog and metadata are adapted from the revision in `data/upstream.json`.
Update the baseline revision, source JSON, geographic resources, client inventory,
fixtures, and catalog counts together. Vendored duplicate JSON keys are normalized
with last-value semantics, matching the upstream parser. Catalog data is packaged; response fixtures
and development tools are not. Keep client signatures synchronized with Ruby
implementations. Native provider modules retain original attribution in NOTICE
and data/ATTRIBUTION.txt.

Public feed checks are explicit: `bundle exec ruby bin/audit-providers --tag
velib --output provider-status.json`, or run the manual GitHub workflow. Omitting
`--tag` checks all predefined networks with two workers. The timeout defaults to
15 seconds per update. Credentials are not used by this audit. Do not capture
private responses or secrets in fixtures, issue reports, logs, or screenshots.

Working catalog entries and unavailable operator feeds are distinct. Retain
retired/unreachable entries and describe the evidence and check date in
PROVIDERS.md. Every fix to a live parser requires an offline regression fixture.
