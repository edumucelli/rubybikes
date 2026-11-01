# RubyBikes

Ruby interface to the maintained [pybikes](https://github.com/eskerda/pybikes)
provider engine. It reads operators directly; the CityBikes public API is not
required. This release replaces the outdated default Ruby adapters with a pinned
Python engine. A complete native Ruby port is deferred.

Requires Ruby 3.1+ and Python 3.11+ for the pinned engine dependencies.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-engine.txt
export RUBYBIKES_PYTHON="$PWD/.venv/bin/python"
bundle install
```

```ruby
require 'rubybikes'

RubyBikes.open do |bikes|
  puts bikes.tags.size
  velib = bikes.get('tag' => 'velib') # Existing factory syntax
  velib.update
  velib.stations.each do |station|
    puts [station.get_hash, station.name, station.bikes, station.free].inspect
  end
  puts velib.to_json
end
```

`get('velib')`, `get(tag: 'velib')`, and `get(label: 'Gbfs')` are also supported.
Labels match the current engine class or module (for example `Bixi` matches the
`bixi` module). Old labels and retired tags may have changed upstream. Station
fields remain `name`, `latitude`, `longitude`, `bikes`, `free`, `timestamp`, and
`extra`. Unknown counts remain `nil`. `get_hash` returns the current pybikes ID;
it differs from the obsolete Ruby hash based on station name. `to_dict`,
`to_json`, and `to_geojson` include stations and free-floating vehicles.

Authenticated providers accept `get(tag: '...', api_key: key)` or a private
`keys:` hash indexed by tag, provider module, or class. Some keys are structured
hashes, as specified by pybikes. Keys travel through a private subprocess pipe.
Provider output and error bodies are suppressed to avoid exposing credentials.

Each factory owns a lazily started Python subprocess. Call `close` or use the
block form `RubyBikes.open`. A factory serializes its requests; use separate
factories for concurrent providers. Updates have a 60-second default hard
deadline, including station detail requests; `RubyBikes.new(timeout: 45)` or
`system.update(timeout: 30)` overrides it. A timeout terminates the process and
the next request starts a new one. Failed updates retain the previous snapshot.
The bridge verifies TLS and limits individual connections and reads to 5 and
20 seconds. It does not retry providers automatically. Rate limits raise
`RubyBikes::RateLimitedError` with `host` and `retry_after`; callers should honor
that cooldown across networks sharing a provider.

`RubyBikes::DependencyError`, `ProviderError`, `TimeoutError`, and `ProtocolError`
identify failures without returning provider response bodies. The original
`NoSystemFoundError`, `NoGetCriteriaError`, and `APIKeyNotAvailableError` names
remain available. Providers can still fail, retire, require keys, or publish
stale data; 815 catalog entries do not imply 815 working public feeds.

The Python revision is pinned in `requirements-engine.txt` and
`lib/rubybikes/engine.json`. Update both together and run:

```sh
bundle exec rake test
.venv/bin/python -m unittest discover -s test/python
```

These checks use the real pinned engine and fixture provider responses, without
contacting live operators. `test/live_providers.rb` preserves the old manual
network probes and is excluded from the default suite. Historical Ruby adapter
files remain for reference and are not loaded by the new facade. There is no
new HTTP server and no public gem publication in this change.

Distributed under the AGPL; see [LICENSE](LICENSE). pybikes retains its own AGPL
license and attribution.
