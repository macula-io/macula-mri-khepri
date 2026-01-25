%%%-------------------------------------------------------------------
%%% @doc
%%% Macula MRI Khepri - Public API module.
%%%
%%% Khepri-based persistence adapter for Macula Resource Identifiers (MRI).
%%% Provides distributed, Raft-consensus storage for MRI registration
%%% and graph relationships.
%%%
%%% == Quick Start ==
%%%
%%% ```
%%% %% Start the application
%%% application:ensure_all_started(macula_mri_khepri).
%%%
%%% %% Register an MRI
%%% ok = macula_mri_khepri:register(<<"mri:app:io.macula/acme/counter">>, #{
%%%     display_name => <<"Counter App">>,
%%%     description => <<"A simple counter">>
%%% }).
%%%
%%% %% Look it up
%%% {ok, Metadata} = macula_mri_khepri:lookup(<<"mri:app:io.macula/acme/counter">>).
%%%
%%% %% Create a relationship
%%% ok = macula_mri_khepri:relate(
%%%     <<"mri:device:io.macula/acme/cabinet-001">>,
%%%     located_at,
%%%     <<"mri:location:io.macula/acme/amsterdam">>
%%% ).
%%%
%%% %% Query relationships
%%% Devices = macula_mri_khepri:related_from(
%%%     <<"mri:location:io.macula/acme/amsterdam">>,
%%%     located_at
%%% ).
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri).

%% Store operations (delegated to macula_mri_khepri_store)
-export([
    register/2,
    lookup/1,
    update/2,
    delete/1,
    exists/1,
    list_children/1,
    list_descendants/1,
    list_by_type/2
]).

%% Graph operations (delegated to macula_mri_khepri_graph)
-export([
    relate/3,
    relate/4,
    unrelate/3,
    related_to/2,
    related_from/2,
    all_related/1,
    all_related_from/1,
    traverse_transitive/3
]).

%% Taxonomy helpers
-export([
    instances_of/1,
    instances_of_transitive/1,
    classes_of/1,
    subclasses/1,
    superclasses/1
]).

%% Administration
-export([
    rebuild_indexes/0
]).

%%====================================================================
%% Store Operations
%%====================================================================

%% @doc Register a new MRI with metadata.
%% @equiv macula_mri_khepri_store:register(MRI, Metadata)
-spec register(binary(), map()) -> ok | {error, term()}.
register(MRI, Metadata) ->
    macula_mri_khepri_store:register(MRI, Metadata).

%% @doc Look up an MRI's metadata.
%% @equiv macula_mri_khepri_store:lookup(MRI)
-spec lookup(binary()) -> {ok, map()} | {error, not_found}.
lookup(MRI) ->
    macula_mri_khepri_store:lookup(MRI).

%% @doc Update an existing MRI's metadata.
%% @equiv macula_mri_khepri_store:update(MRI, Metadata)
-spec update(binary(), map()) -> ok | {error, term()}.
update(MRI, Metadata) ->
    macula_mri_khepri_store:update(MRI, Metadata).

%% @doc Delete an MRI.
%% @equiv macula_mri_khepri_store:delete(MRI)
-spec delete(binary()) -> ok | {error, term()}.
delete(MRI) ->
    macula_mri_khepri_store:delete(MRI).

%% @doc Check if an MRI exists.
%% @equiv macula_mri_khepri_store:exists(MRI)
-spec exists(binary()) -> boolean().
exists(MRI) ->
    macula_mri_khepri_store:exists(MRI).

%% @doc List direct children of an MRI.
%% @equiv macula_mri_khepri_store:list_children(MRI)
-spec list_children(binary()) -> [binary()].
list_children(MRI) ->
    macula_mri_khepri_store:list_children(MRI).

%% @doc List all descendants of an MRI.
%% @equiv macula_mri_khepri_store:list_descendants(MRI)
-spec list_descendants(binary()) -> [binary()].
list_descendants(MRI) ->
    macula_mri_khepri_store:list_descendants(MRI).

%% @doc List all MRIs of a given type in a realm.
%% @equiv macula_mri_khepri_store:list_by_type(Type, Realm)
-spec list_by_type(atom(), binary()) -> [binary()].
list_by_type(Type, Realm) ->
    macula_mri_khepri_store:list_by_type(Type, Realm).

%%====================================================================
%% Graph Operations
%%====================================================================

%% @doc Create a relationship between two MRIs.
%% @equiv macula_mri_khepri_graph:create_relationship(Subject, Predicate, Object)
-spec relate(binary(), atom() | {custom, binary()}, binary()) -> ok | {error, term()}.
relate(Subject, Predicate, Object) ->
    macula_mri_khepri_graph:create_relationship(Subject, Predicate, Object).

%% @doc Create a relationship with metadata.
%% @equiv macula_mri_khepri_graph:create_relationship(Subject, Predicate, Object, Metadata)
-spec relate(binary(), atom() | {custom, binary()}, binary(), map()) -> ok | {error, term()}.
relate(Subject, Predicate, Object, Metadata) ->
    macula_mri_khepri_graph:create_relationship(Subject, Predicate, Object, Metadata).

%% @doc Delete a relationship.
%% @equiv macula_mri_khepri_graph:delete_relationship(Subject, Predicate, Object)
-spec unrelate(binary(), atom() | {custom, binary()}, binary()) -> ok | {error, term()}.
unrelate(Subject, Predicate, Object) ->
    macula_mri_khepri_graph:delete_relationship(Subject, Predicate, Object).

%% @doc Get all objects related to subject via predicate.
%% @equiv macula_mri_khepri_graph:related_to(Subject, Predicate)
-spec related_to(binary(), atom() | {custom, binary()}) -> [binary()].
related_to(Subject, Predicate) ->
    macula_mri_khepri_graph:related_to(Subject, Predicate).

%% @doc Get all subjects related to object via predicate.
%% @equiv macula_mri_khepri_graph:related_from(Object, Predicate)
-spec related_from(binary(), atom() | {custom, binary()}) -> [binary()].
related_from(Object, Predicate) ->
    macula_mri_khepri_graph:related_from(Object, Predicate).

%% @doc Get all relationships from a subject.
%% @equiv macula_mri_khepri_graph:all_related(Subject)
-spec all_related(binary()) -> [{atom() | {custom, binary()}, binary()}].
all_related(Subject) ->
    macula_mri_khepri_graph:all_related(Subject).

%% @doc Get all relationships to an object.
%% @equiv macula_mri_khepri_graph:all_related_from(Object)
-spec all_related_from(binary()) -> [{atom() | {custom, binary()}, binary()}].
all_related_from(Object) ->
    macula_mri_khepri_graph:all_related_from(Object).

%% @doc Traverse transitively (follow all edges of type).
%% @equiv macula_mri_khepri_graph:traverse_transitive(Start, Predicate, Direction)
-spec traverse_transitive(binary(), atom() | {custom, binary()}, forward | reverse) -> [binary()].
traverse_transitive(Start, Predicate, Direction) ->
    macula_mri_khepri_graph:traverse_transitive(Start, Predicate, Direction).

%%====================================================================
%% Taxonomy Helpers
%%====================================================================

%% @doc Get direct instances of a class.
-spec instances_of(binary()) -> [binary()].
instances_of(Class) ->
    macula_mri_khepri_graph:instances_of(Class).

%% @doc Get all instances including subclasses (transitive).
-spec instances_of_transitive(binary()) -> [binary()].
instances_of_transitive(Class) ->
    macula_mri_khepri_graph:instances_of_transitive(Class).

%% @doc Get classes of an instance.
-spec classes_of(binary()) -> [binary()].
classes_of(Instance) ->
    macula_mri_khepri_graph:classes_of(Instance).

%% @doc Get direct subclasses of a class.
-spec subclasses(binary()) -> [binary()].
subclasses(Class) ->
    macula_mri_khepri_graph:subclasses(Class).

%% @doc Get direct superclasses of a class.
-spec superclasses(binary()) -> [binary()].
superclasses(Class) ->
    macula_mri_khepri_graph:superclasses(Class).

%%====================================================================
%% Administration
%%====================================================================

%% @doc Rebuild all indexes (useful after data import or corruption).
-spec rebuild_indexes() -> ok.
rebuild_indexes() ->
    macula_mri_khepri_index:rebuild_indexes().
