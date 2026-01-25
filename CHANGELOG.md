# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/macula-io/macula-mri-khepri/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/macula-io/macula-mri-khepri/releases/tag/v0.1.0
