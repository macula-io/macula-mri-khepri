# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.3] - 2026-01-31

### Changed

- **Khepri Dependency Update**
  - Updated khepri from 0.16.0 to 0.17.2 for compatibility with reckon_db ecosystem
  - Ensures dependency resolution in projects using both macula_mri_khepri and reckon_db
  - All tests passing (88 tests, 0 failures)

---

## [0.4.2] - 2026-01-30

### Fixed

- **Hexdocs Image Path**
  - Fixed SVG asset path in guide for hexdocs rendering
  - Changed `../assets/` to `assets/` for correct URL resolution

---

## [0.4.1] - 2026-01-30

### Changed

- **Renamed Demo Module**
  - Renamed `macula_mri_khepri_proximus_demo` to `macula_mri_khepri_telcox_demo`
  - Replaced all "Proximus" references with "TelcoX" (trademark compliance)

### Fixed

- **Documentation Assets**
  - Fixed SVG assets not appearing in hexdocs
  - Added proper ex_doc configuration for asset paths

---

## [0.4.0] - 2026-01-29

### Added

- **Macula Core Integration**
  - Added `macula ~> 0.20.5` dependency
  - Enabled `macula_mri_store` behaviour in `macula_mri_khepri_store`
  - Enabled `macula_mri_graph` behaviour in `macula_mri_khepri_graph`
  - Full compatibility with macula's MRI type system including new `instance` type

- **New Behaviour Callbacks**
  - `get_relationship/3,4` - Retrieve relationship with metadata (macula_mri_graph behaviour)
  - `list_by_realm/1,2` - List all MRIs in a realm (macula_mri_store behaviour)

### Changed

- Removed TODO comments for behaviour declarations (now implemented)

---

## [0.3.0] - 2026-01-26

### Added

- **Pagination Support** for list functions
  - `list_children_opts/2,3` with `#{limit, offset}` options
  - `list_descendants_opts/2,3` with `#{limit, offset}` options
  - `list_by_type_opts/3,4` with `#{limit, offset}` options
  - Default limit of 1000 results per query
  - Backwards-compatible: existing functions unchanged

- **Depth-Limited Graph Traversal**
  - `traverse_transitive_opts/4,5` with `#{max_depth}` option
  - Default max_depth of 100 to prevent stack overflow
  - Protects against deep/infinite graph traversal

- **Shared MRI Parsing Module** (`macula_mri_khepri_parse`)
  - Extracted duplicated `parse_mri/1` from `_store.erl` and `_index.erl`
  - Uses safer `binary_to_existing_atom` with fallback
  - Internal module (not part of public API)

- **Index Fallback Warning**
  - `list_by_type` now logs a warning when type index is missing
  - Helps identify missing indexes in production

### Changed

- **Config-Driven Indexing**
  - `enable_type_index` and `enable_realm_index` configs now actually used
  - Can disable specific indexes via application config

- **Simplified Index Initialization**
  - Removed redundant root node creation in `ensure_index_structure/1`
  - Khepri auto-creates paths on write; no pre-initialization needed

### Fixed

- DRY violation: `parse_mri/1` was duplicated across modules
- Unused config: `enable_type_index` and `enable_realm_index` were defined but never read
- Potential memory exhaustion: list functions now have default limits

## [0.2.0] - 2026-01-26

### Added

- **Interactive TUI Demo** (`macula_mri_khepri_tui`)
  - Real-time network generation with progress visualization
  - Live statistics table by Belgian region
  - Performance benchmarking with color-coded metrics
  - Adjustable scale from 1% to 100%
  - Keyboard navigation: [G]enerate, [Q]uery, [B]enchmark, [C]lear
  - Launch with `./scripts/demo.sh`

- **TelcoX Scale Demo** (`macula_mri_khepri_telcox_demo`)
  - Belgian telecom network simulation
  - ~4,000 street cabinets (SRPs) at full scale
  - ~1,000,000 home connections at full scale
  - `generate_network/2` with configurable scale
  - `count_by_region/1`, `list_srps_in_region/2`, `list_homes_for_srp/2`
  - `benchmark/2` for performance testing

- **Integration Tests** (23 new tests)
  - Real Khepri store tests (no mocks)
  - Full CRUD, tree queries, bulk operations
  - Graph relationships with cycle detection
  - Taxonomy helpers verification

### Fixed

- Khepri 0.16+ error format compatibility (`{error, {khepri, ...}}`)
- Transaction return value handling (`{ok, Result}` unwrapping)
- Horus restriction for `erlang:system_time/1` in transactions
- Cycle detection in `traverse_transitive` for graphs with loops
- MRI type parsing with `binary_to_atom` for new types

### Changed

- Test count: 54 → 82 tests (all passing)

## [0.1.0] - 2026-01-25

### Added

- Initial release
- `macula_mri_khepri_store` - Khepri-based MRI storage
  - CRUD operations: `register/2`, `lookup/1`, `update/2`, `delete/1`, `exists/1`
  - Tree queries: `list_children/1`, `list_descendants/1`, `list_by_type/2`
  - Bulk operations: `import/1`, `export_subtree/1`
- `macula_mri_khepri_graph` - Graph relationship storage
  - Relationship CRUD: `create_relationship/3,4`, `delete_relationship/3`
  - Forward queries: `related_to/2`, `all_related/1`
  - Reverse queries: `related_from/2`, `all_related_from/1`
  - Traversal: `traverse/3`, `traverse_transitive/3`
- `macula_mri_khepri_index` - Secondary index management
  - Type indexes for fast `list_by_type` queries
  - Realm indexes for fast realm-scoped queries
  - `rebuild_indexes/0` for recovery
- Taxonomy helpers
  - `instances_of/1`, `instances_of_transitive/1`
  - `classes_of/1`, `subclasses/1`, `superclasses/1`
- Public API module `macula_mri_khepri` with delegating functions
- Umbrella project structure (`apps/macula_mri_khepri/`)
- Comprehensive test suite (54 tests)
  - Store tests: CRUD, tree queries, bulk operations, MRI parsing
  - Graph tests: relationships, traversal, cycle handling, taxonomy
  - Index tests: GenServer lifecycle, structure initialization

### Dependencies

- Khepri 0.16.0

[Unreleased]: https://github.com/macula-io/macula-mri-khepri/compare/v0.4.2...HEAD
[0.4.2]: https://github.com/macula-io/macula-mri-khepri/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/macula-io/macula-mri-khepri/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/macula-io/macula-mri-khepri/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/macula-io/macula-mri-khepri/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/macula-io/macula-mri-khepri/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/macula-io/macula-mri-khepri/releases/tag/v0.1.0
