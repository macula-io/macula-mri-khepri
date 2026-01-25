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
    {macula_mri_khepri, "0.1.0"}
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

## License

Apache-2.0. See [LICENSE](LICENSE).

## Links

- [Macula Platform](https://macula.io)
- [MRI Design Document](https://github.com/macula-io/macula-console/blob/main/plans/DESIGN_MACULA_RESOURCE_IDENTIFIERS.md)
- [Khepri](https://github.com/rabbitmq/khepri)
