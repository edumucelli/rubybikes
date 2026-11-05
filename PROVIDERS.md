# Provider support and live status

Public checks recorded on **2026-11-04 and 2026-11-05 (UTC)**. RubyBikes implements the **85 concrete clients**
and preserves the **815 predefined networks** from PyBikes baseline
[`b8681d2344d2ccc61d7b99b089a8cdba167a169e`](https://github.com/eskerda/pybikes/commit/b8681d2344d2ccc61d7b99b089a8cdba167a169e).
The upstream snapshot and attribution are included in the gem's `data/` directory.

## What provider coverage means

Release checks require a successful, nonempty offline fixture update from every
client, as well as construction of all predefined networks. Fixtures exercise
real native Ruby parsers, expected station/vehicle fields, and HTTP request
shapes; external HTTP is disabled in these tests. CI also enforces 95% Ruby line
coverage and reports branch coverage.

This is different from live availability. An operator may retire an endpoint,
put a website into maintenance, require credentials, or reject requests from a
particular network. The catalog retains these networks and their implementations
rather than silently dropping them or returning fabricated availability.

Four supported clients have no predefined networks in the baseline:
`NextbikeGbfs`, `KeolisIlevia`, `VCub`, and `OTP`. Use `build` with the client's
constructor parameters to configure them. Authenticated clients have fixture
coverage; their live status remains **requires credentials** unless tested with
operator-issued access. Public audits do not send placeholder credentials.

Discover the packaged catalog without contacting operators:

```sh
bundle exec ruby -Ilib -rrubybikes -e 'RubyBikes.open { |b| puts b.providers.map { |p| [p["module"], p["class"], p["tags"].size].join("\t") } }'
```

## Verified public feed repairs

These changes preserve existing network tags and include offline regression
fixtures. Counts below are observations at the check time, not fixed expectations
for future operator responses.

| Network/client | Repair | Verified result |
| --- | --- | --- |
| `meiob` / Meiob | Parse padded decimal availability, including `08` and `09`, without Ruby's implicit octal interpretation. | 77 stations |
| `mibisivalencia` / Movus | Follow the official station page's map script to its JSON feed; accept spaced count labels and the accented `Actualizándose` state. Retain the older embedded marker format. | 30 stations |
| `bicisanvi` / Movus | Discover the current map script and its `/php/puntos.php` JSON endpoint using the same native implementation. | 14 stations |
| `publibike-aargau` / Publibike | Ignore null canton geometries before geographic filtering, matching the upstream behavior. Verified on 2026-11-05. | 68 stations |
| `publibike-bern` / Publibike | Apply the same null-geometry correction to both PubliBike and Velospot station formats. Verified on 2026-11-05. | 395 stations |
| `publibike-fribourg` / Publibike | Apply the same null-geometry correction. Verified on 2026-11-05. | 63 stations |

The native Samba implementation reads provider data with a restricted literal
parser. It accepts the published arrays, tuples, strings, and numeric values;
it does not evaluate scripts or execute provider-supplied expressions.

## Selected successful live checks

These public, bounded probes successfully parsed nonempty native snapshots on
2026-11-04. They are selected checks rather than a statement that every one of
the 815 catalog networks was available.

| Network | Client | Stations observed |
| --- | --- | ---: |
| `bicielx` | BiciElx | 114 |
| `bici-ferrol-terra` | BiciFerrolTerra | 18 |
| `girocleta` | Emovity | 36 |
| `passofundo` | Mobhis | 8 |
| `velobike` | VelobikeKZ | 152 |
| `bicicuenca` | Samba | 20 |

## Known live access issues

The following observations were made on 2026-11-04 unless stated otherwise. They
do not disable fixture-tested clients or remove their
catalog entries. A timeout or HTTP denial describes the checking environment;
it is not proof that a service is permanently retired.

| Network | Public endpoint checked | Dated observation |
| --- | --- | --- |
| `gyorbike` | <https://www.gyorbike.hu/en/stations> | HTTP 200, but the operator serves “Karbantartás alatt / This page is under construction” with no station table or marker data. |
| `bikeu-bra` | <https://www.bra.org.pl/mapa-stacji.html> | Connection timed out at the five-second connection bound. No replacement feed was verified. |
| `bicicletar` | <https://www.bicicletar.com.br/mapaestacao.aspx> | HTTP 403. The baseline HTTP address and its HTTPS equivalent both rejected access. |
| `bikesantos` | <https://www.mobilicidade.com.br/bikesantos/mapaestacao.aspx> | HTTP 403 over HTTPS; no accessible replacement verified. |
| `bikevitoria` | <https://www.bikevitoria.com/mapaestacao.aspx> | HTTP 403; no accessible replacement verified. |
| Legacy EasyBike entries listed below | `http://reseller.easybike.gr/{city_uid}/api.php` | On 2026-11-05, HTTP 200 with `stations: null`: the endpoint publishes no station feed. No public replacement was verified. |

The affected legacy EasyBike entries are `athens-bikes`, `easybike-didymoteicho`,
`easybike-glyfada`, `easybike-igoumenitsa`, `easybike-ioannina`,
`easybike-karditsa`, `easybike-kinouria`, `easybike-komotini`, `easybike-patra`,
`easybike-rethymno`, and `easybike-samos`. The separate `easybike-mani` feed still
returned two stations in the same check. A null feed raises an explicit provider
error; a valid empty station array remains an empty snapshot.

Do not disable TLS verification or treat an HTML error/maintenance page as an
empty working bike network to make an audit pass. Preserve the previous snapshot
when an update fails.

## Run a fresh public audit

Install the development dependencies, then audit a single network or the full
catalog:

```sh
bundle install
bundle exec ruby bin/audit-providers --tag velib --timeout 15 --output /tmp/rubybikes-velib-status.json
bundle exec ruby bin/audit-providers --timeout 15 --output /tmp/rubybikes-provider-status.json
```

The audit uses two workers, bounds connection/read time within each network's
update deadline, honors provider rate-limit cooldowns, and records UTC check
times, client names, statuses, and station/vehicle counts. It marks authenticated
entries `requires_credentials` rather than calling them with dummy keys. Output
statuses include `working`, `empty`, `timeout`, `rate_limited`, `error`, and
`requires_credentials`. Error reports exclude provider response bodies and
credential-bearing URLs.

The **Audit public provider feeds** GitHub Actions workflow provides the same
manual check. Supply a network tag for a targeted probe, or leave it empty for
all predefined networks; download the `provider-status` artifact afterward.
The JSON report is written incrementally and includes a `complete` flag; partial
results remain available if an audit is interrupted. Live audits are deliberately separate from pull-request and release test gates,
so an operator outage does not make deterministic fixture tests fail.

When repairing a changed feed, keep its existing tag, verify the operator's
published endpoint, add a sanitized response fixture and explicit expected
fields, and record the dated live result. Never commit provider credentials or
RubyGems recovery codes.
