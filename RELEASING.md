# Releasing RubyBikes

Publishing uses the `release.yml` workflow in `edumucelli/rubybikes`, environment
`release`, and immutable RubyGems owner **255571**. Configure a pending trusted
publisher under that RubyGems account for the first release, or an existing-gem
trusted publisher for later releases. Enable MFA on the RubyGems account.

The pending publisher described during setup expires after about twelve hours.
If it expires before the first release, recreate it before tagging. Do not
release incomplete code merely to use an expiring publisher.

The public RubyGems action versions inspected during development do not expose
an owner input. `.github/scripts/configure_rubygems.rb` performs the documented
OIDC exchange directly, sending `{jwt: ..., owner: 255571}`. It masks the
short-lived API key and passes it through the temporary Actions environment
file. No long-lived API key is stored in repository secrets or a credentials
file. A future migration to an official action must verify that the action
actually forwards the owner input, especially for the first push.

1. Update `RubyBikes::VERSION` and the changelog through a reviewed commit on
   `master`. Check that the version has not already been published.
2. Ensure native tests, all-client fixture verification, 95% coverage, lint,
   type checks, and the installed-package smoke test pass.
3. Create and push a matching version tag, e.g. `v0.3.0`, to GitHub only.
4. The tag workflow reruns CI, checks tag/version agreement and master ancestry,
   builds and verifies the package, exchanges OIDC credentials for the configured
   owner, publishes to RubyGems, and creates a GitHub release with the gem attached.

A failed validation or failed CI run cannot publish. A RubyGems push failure
prevents GitHub release creation. If publication succeeded but GitHub release
creation failed, create the release for that existing tag without republishing
or overwriting the gem. RubyGems versions are immutable.

This repository update does not itself create a tag or publish a gem.
