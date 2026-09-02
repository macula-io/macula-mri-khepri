# macula-mri-khepri

[![Hex.pm](https://img.shields.io/hexpm/v/macula_mri_khepri.svg)](https://hex.pm/packages/macula_mri_khepri)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/macula_mri_khepri)

Khepri-based persistence adapter for [Macula Resource Identifiers (MRI)](https://github.com/macula-io/macula).

Provides distributed, Raft-consensus storage for MRI registration and graph relationships.

## Features

- **Tree-based storage** - MRIs stored hierarchically, matching their natural structure
- **Raft consensus** - Distributed consistency via [Khepri](https://github.com/rabbitmq/khepri) / [Ra](https://github.com/rabbitmq/ra)
- **Graph relationships** - Bidirectional relationship storage with efficient traversal
- **Secondary indexes** - Fast queries by type, realm, and custom attributes
- **Taxonomy support** - Built-in helpers for `instance_of`, `subclass_of` relationships

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {macula_mri_khepri, "0.4.2"}
]}.
```

## Quick Start

```erlang
%% Start the application
application:ensure_all_started(macula_mri_khepri).

%% Register an MRI
ok = macula_mri_khepri:register(<<"mri:app:io.macula/acme/counter">>, #{
    display_name => <<"Counter App">>,
    description => <<"A simple counter">>
}).

%% Look it up
{ok, Metadata} = macula_mri_khepri:lookup(<<"mri:app:io.macula/acme/counter">>).

%% List all apps in realm
Apps = macula_mri_khepri:list_by_type(app, <<"io.macula">>).
```

## Graph Relationships

```erlang
%% Create a relationship
ok = macula_mri_khepri:relate(
    <<"mri:device:io.macula/acme/cabinet-001">>,
    located_at,
    <<"mri:location:io.macula/acme/amsterdam">>
).

%% Query: all devices at a location
Devices = macula_mri_khepri:related_from(
    <<"mri:location:io.macula/acme/amsterdam">>,
    located_at
).

%% Transitive traversal (e.g., all dependencies)
AllDeps = macula_mri_khepri:traverse_transitive(
    <<"mri:app:io.macula/acme/frontend">>,
    depends_on,
    forward
).
```

## Taxonomy Support

```erlang
%% Define class hierarchy
ok = macula_mri_khepri:relate(
    <<"mri:class:io.macula/street-cabinet">>,
    subclass_of,
    <<"mri:class:io.macula/edge-device">>
).

%% Mark an instance
ok = macula_mri_khepri:relate(
    <<"mri:device:io.macula/acme/cabinet-001">>,
    instance_of,
    <<"mri:class:io.macula/street-cabinet">>
).

%% Query all instances of edge-device (including subclasses)
AllEdgeDevices = macula_mri_khepri:instances_of_transitive(
    <<"mri:class:io.macula/edge-device">>
).
```

## Configuration

```erlang
%% In sys.config or application env
{macula_mri_khepri, [
    {store_name, mri_store},
    {data_dir, "/var/lib/macula/mri"},
    {cluster_name, macula_mri_cluster}
]}.
```

## Architecture

This package implements storage behaviours defined in `macula`:

```
macula/                          macula_mri_khepri/
├── macula_mri_store (behaviour) ◄── macula_mri_khepri_store (impl)
└── macula_mri_graph (behaviour) ◄── macula_mri_khepri_graph (impl)
```

The separation keeps `macula/` lightweight (no Khepri/Ra dependency) while providing a production-ready distributed storage option.

## Storage Schema

### MRI Tree

```
[mri, Type, Realm, Segment1, Segment2, ...]

Example:
mri:app:io.macula/acme/counter
→ [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>]
```

### Relationships

```
Forward: [mri_rel, forward, Subject, Predicate, Object] → Metadata
Reverse: [mri_rel, reverse, Object, Predicate, Subject] → Metadata
```

### Indexes

```
[mri_index, by_type, Type, Realm, MRI] → true
[mri_index, by_realm, Realm, MRI] → true
```

## Interactive TUI Demo

Launch the interactive terminal demo:

```bash
./scripts/demo.sh
```

```
╭────────────────────────────────────────────────────────────╮
│  MACULA MRI - TelcoX Network Scale Demo                  │
╰────────────────────────────────────────────────────────────╯

  Scale: 10% (press +/- to adjust)
  Status: Ready  [████████████████████████████████████████] 100%

  Network Topology
  ┌──────────────┬──────────┬────────────┬────────────┐
  │ Region       │ SRPs     │ Homes      │ Status     │
  ├──────────────┼──────────┼────────────┼────────────┤
  │ Brussels     │       40 │     10.0K  │ ✓ Complete │
  │ Flanders     │      220 │     55.0K  │ ✓ Complete │
  │ Wallonia     │      140 │     35.0K  │ ✓ Complete │
  └──────────────┴──────────┴────────────┴────────────┘
  Total: 400 SRPs, 100.0K Homes

  Performance Metrics
  ├── SRP Lookup:      45.2 µs
  ├── List Children:   1.2 ms
  ├── Type Query:      8.3 ms
  └── Region Count:    12.1 ms

  [G]enerate  [Q]uery  [B]enchmark  [C]lear  [+/-] Scale  [X] Exit
```

**Controls:**
- `G` - Generate network at current scale
- `Q` - Run sample query
- `B` - Run performance benchmark
- `C` - Clear network data
- `+`/`-` - Adjust scale (1% to 100%)
- `X` or `ESC` - Exit

## Scale Demo: TelcoX Network (Programmatic)

The package also includes a programmatic demo module:

```erlang
%% Generate a scaled network (1% = ~40 SRPs, ~10K homes)
{ok, Stats} = macula_mri_khepri_telcox_demo:generate_network(mri_store, #{
    scale => 0.01  %% 1% of full scale
}).

%% Query by region
Counts = macula_mri_khepri_telcox_demo:count_by_region(mri_store).
%% => #{<<"brussels">> => #{srps => 4, homes => 1000}, ...}

%% List SRPs in a region
Srps = macula_mri_khepri_telcox_demo:list_srps_in_region(mri_store, <<"flanders">>).

%% Run benchmark
macula_mri_khepri_telcox_demo:benchmark(mri_store, #{
    scale => 0.1,       %% 10% scale (~400 SRPs, ~100K homes)
    iterations => 100
}).
```

At full scale, this models:
- ~4,000 street cabinets (SRPs)
- ~1,000,000 home connections
- Demonstrates trie index performance at realistic scale

## Documentation

- **[MRI Core Guide](https://github.com/macula-io/macula/blob/main/guides/mri.md)** - MRI format, types, behaviours, extensibility
- **[Khepri Adapter Guide](guides/mri-system-guide.md)** - Storage schema, API usage, configuration, troubleshooting

## License

Apache-2.0. See [LICENSE](LICENSE).

## Links

- [Macula Platform](https://macula.io)
- MRI Design Document (archived with the deprecated `macula-console` repo)
- [Khepri](https://github.com/rabbitmq/khepri)
- [Ra (Raft)](https://github.com/rabbitmq/ra)
