# Releasing RubyBikes

Publishing uses the `release.yml` workflow in `edumucelli/rubybikes`, environment
`release`, and immutable RubyGems owner **255571**. Configure a pending trusted
publisher under that RubyGems account for the first release, or an existing-gem
trusted publisher for later releases. Enable MFA on the RubyGems account.

The pending publisher described during setup expires after about twelve hours.
If it expires before the first release, recreate it before publishing. Do not
release incomplete code merely to use an expiring publisher.

The public RubyGems action versions inspected during development do not expose
an owner input. `.github/scripts/configure_rubygems.rb` performs the documented
OIDC exchange directly, sending `{jwt: ..., owner: 255571}`. It masks the
short-lived API key and passes it through the temporary Actions environment
file. No long-lived API key is stored in repository secrets or a credentials
file. A future migration to an official action must verify that the action
actually forwards the owner input, especially for the first push.

1. Bump `RubyBikes::VERSION` in `lib/rubybikes/version.rb` and update the
   changelog, then push or merge the commit into `master` on GitHub.
2. The release workflow runs native tests, all-client fixture verification,
   95% coverage, lint, type checks, and the installed-package smoke test.
3. After CI passes, the workflow reads the version from that file and checks
   RubyGems. Already published versions are skipped; registry errors fail the
   release instead of treating the version as available.
4. For an unpublished version, it verifies master ancestry, builds and checks
   the package, exchanges OIDC credentials for owner **255571**, and publishes
   to RubyGems. It then creates the matching tag (for example `v0.3.0`) at the
   tested commit and a GitHub release with the gem attached. An existing tag
   pointing to a different commit blocks publication.

No manual tag is needed. Changes to `release.yml` also trigger the workflow,
allowing the initial `0.3.0` release without a redundant version bump. To retry
an unpublished version after fixing a release problem, run `release.yml`
manually with `workflow_dispatch` on `master`.

A failed validation or failed CI run cannot publish. A RubyGems push failure
prevents GitHub release creation. If publication succeeded but GitHub release
creation failed, create the release at the published commit without republishing
or overwriting the gem. RubyGems versions are immutable; rerunning the workflow
skips a version that is already on RubyGems.
