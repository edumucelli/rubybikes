# RubyBikes

Native Ruby clients for bike-sharing stations and free-floating vehicles. The
catalog contains **815 networks in 53 countries**, backed by **85 provider
clients** adapted from [PyBikes](https://github.com/eskerda/pybikes). Operators are
queried directly; no CityBikes API service or Python installation is required.

Requires Ruby **3.1 or newer**. Install with `gem install rubybikes`, or add
`gem 'rubybikes'` to your application's Gemfile. Version 0.3.0 is being prepared;
installation from RubyGems becomes available after its first release.

```ruby
require 'rubybikes'

RubyBikes.open do |bikes|
  network = bikes.get('velib')
  network.update
  network.stations.each do |station|
    puts [station.id, station.name, station.bikes, station.free].inspect
  end
  puts network.to_json
end
```

`get('velib')`, `get(tag: 'velib')`, and the original `get('tag' => 'velib')`
are equivalent. `get(label: 'Gbfs')` returns matching networks. `tags`, `labels`,
`catalog`, and `providers` provide discovery without contacting operators.
Provider records include module/class names, tags, and `authed`, `sync`, and
`unifeed` flags. Each system exposes `provider` and `client_class`.

```ruby
RubyBikes.open do |bikes|
  system = bikes.build(
    provider: 'NextbikeGbfs', tag: 'custom-ambici', domain: 'bs',
    meta: { name: 'Ambici', city: 'Barcelona', country: 'ES' }
  )
  system.update
end
```

Custom definitions accept upstream constructor parameter names. Class names take
precedence over module names, case-insensitively. Specify `class_name:` for a
module with multiple clients, for example `provider: 'keolis', class_name: 'VCub'`.
All 85 clients are supported, including the four without predefined networks:
`NextbikeGbfs`, `KeolisIlevia`, `VCub`, and `OTP`.

Stations expose `id` (`get_hash`), `name`, `latitude`, `longitude`, `bikes`,
`free`, UTC `timestamp`, and provider-specific `extra`. Unknown counts remain
`nil`. Vehicles expose coordinates, `kind`, identity, timestamp, and `extra`.
Systems, stations, and vehicles support `to_h`/`to_dict`, `to_json`, and
`to_geojson`. Station IDs retain the PyBikes coordinate-based MD5 convention;
vehicle IDs retain their network and vehicle identity components.

Authenticated clients accept `api_key:` in `get` or `build`. Alternatively,
configure `RubyBikes.new(keys: { provider_module => credentials })`; tag and
class-name keys are also accepted. Resolution prefers an explicit key, then a
network-tag key, provider-module key, and finally a client-class key. Structured keys
retain the upstream field names, such as BiciMAD `clientid`/`passkey` and Weelo
`client_id`/`client_secret`. Never commit provider credentials.

Updates have a default 60-second overall deadline; use `RubyBikes.new(timeout:
45)` or `system.update(timeout: 30)` to override it. Individual connections and
reads are bounded to 5 and 20 seconds and share the update deadline. TLS is
verified, HTTP redirects are bounded, cookies are scoped, and rate limits raise
`RubyBikes::RateLimitedError` with `host` and `retry_after`. Authentication refresh
is supported; failed provider requests are not automatically retried. Failed
updates retain the previous complete Ruby snapshot. A factory serializes its
updates; use separate factories for concurrent networks.

Errors use `RubyBikes::ProviderError`, `TimeoutError`, `ProtocolError`,
`NoSystemFoundError`, `NoGetCriteriaError`, and `APIKeyNotAvailableError`.
Provider response bodies and credential-bearing URLs are excluded from error
messages. Original top-level exception aliases remain available.

## Development

```sh
bin/setup
bundle exec rake test build
ruby .github/scripts/package_smoke.rb
```

Tests use Minitest, WebMock, and checked-in response fixtures; external requests
are disabled. CI requires a successful nonempty fixture update from every client,
constructs all 815 catalog networks, and enforces 95% line coverage with branch
coverage reported. Type definitions ship in `sig/`.

Quality tooling uses Ruby 3.4 and a separate bundle so runtime compatibility can
remain Ruby 3.1+:

```sh
BUNDLE_GEMFILE=gemfiles/quality.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/quality.gemfile bundle exec rake lint typecheck
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for provider changes,
[PROVIDERS.md](PROVIDERS.md) for live status and known issues, and
[RELEASING.md](RELEASING.md) for publishing.

## Migrating from 0.2

The Python subprocess and its requirements have been removed. Delete any
`python:` constructor argument and `RUBYBIKES_PYTHON` configuration. `engine_info`
now reports `implementation: 'ruby'`, the gem version, and the upstream baseline
revision. `close` and the block form remain supported; no child process is used.
The old direct-require adapter files were retired; use the RubyBikes factory.

Distributed under AGPL-3.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and the
preserved upstream attribution in `data/ATTRIBUTION.txt`.
