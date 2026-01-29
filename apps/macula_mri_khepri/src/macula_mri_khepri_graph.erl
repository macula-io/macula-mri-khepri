%%%-------------------------------------------------------------------
%%% @doc
%%% Khepri-based graph relationships for Macula Resource Identifiers.
%%%
%%% Implements the macula_mri_graph behaviour using Khepri storage
%%% with bidirectional indexes for efficient traversal.
%%%
%%% == Storage Schema ==
%%%
%%% Relationships are stored with forward and reverse indexes:
%%% ```
%%% Forward:  [mri_rel, forward, Subject, Predicate, Object] -> Metadata
%%% Reverse:  [mri_rel, reverse, Object, Predicate, Subject] -> Metadata
%%% '''
%%%
%%% This enables efficient queries in both directions:
%%% - "What is X related to?" (forward)
%%% - "What is related to X?" (reverse)
%%%
%%% == Depth Limit ==
%%%
%%% Transitive traversal supports an optional `max_depth' to prevent
%%% stack overflow on deep graphs:
%%% ```
%%% traverse_transitive_opts(Start, Predicate, Direction, #{max_depth => 10})
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_graph).

-behaviour(macula_mri_graph).

-export([
    %% Relationship CRUD
    create_relationship/3,
    create_relationship/4,
    create_relationship/5,
    delete_relationship/3,
    delete_relationship/4,
    relationship_exists/3,
    relationship_exists/4,
    get_relationship/3,
    get_relationship/4,

    %% Forward queries (subject -> objects)
    related_to/2,
    related_to/3,
    all_related/1,
    all_related/2,

    %% Reverse queries (object -> subjects)
    related_from/2,
    related_from/3,
    all_related_from/1,
    all_related_from/2,

    %% Graph traversal (backwards compatible)
    traverse/3,
    traverse/4,
    traverse_transitive/3,
    traverse_transitive/4,

    %% Graph traversal with options
    traverse_transitive_opts/4,
    traverse_transitive_opts/5,

    %% Taxonomy helpers
    instances_of/1,
    instances_of/2,
    instances_of_transitive/1,
    instances_of_transitive/2,
    classes_of/1,
    classes_of/2,
    subclasses/1,
    subclasses/2,
    superclasses/1,
    superclasses/2
]).

-define(DEFAULT_STORE, mri_store).
-define(DEFAULT_MAX_DEPTH, 100).

-include_lib("khepri/include/khepri.hrl").

%%====================================================================
%% Types
%%====================================================================

-type mri() :: binary().
-type predicate() :: atom() | {custom, binary()}.
-type metadata() :: map().
-type store() :: atom().
-type direction() :: forward | reverse.
-type traverse_opts() :: #{
    max_depth => pos_integer()
}.

%%====================================================================
%% Relationship CRUD
%%====================================================================

%% @doc Create a relationship between two MRIs.
-spec create_relationship(mri(), predicate(), mri()) -> ok | {error, term()}.
create_relationship(Subject, Predicate, Object) ->
    create_relationship(?DEFAULT_STORE, Subject, Predicate, Object, #{}).

-spec create_relationship(mri(), predicate(), mri(), metadata()) -> ok | {error, term()}.
create_relationship(Subject, Predicate, Object, Metadata) ->
    create_relationship(?DEFAULT_STORE, Subject, Predicate, Object, Metadata).

-spec create_relationship(store(), mri(), predicate(), mri(), metadata()) -> ok | {error, term()}.
create_relationship(Store, Subject, Predicate, Object, Metadata) ->
    Now = erlang:system_time(millisecond),
    Data = Metadata#{
        subject => Subject,
        predicate => Predicate,
        object => Object,
        created_at => Now
    },

    %% Store in both directions for bidirectional queries
    ForwardPath = [mri_rel, forward, Subject, Predicate, Object],
    ReversePath = [mri_rel, reverse, Object, Predicate, Subject],

    %% khepri:transaction returns {ok, TransactionResult} or {error, ...}
    case khepri:transaction(Store, fun() ->
        khepri_tx:put(ForwardPath, Data),
        khepri_tx:put(ReversePath, Data)
    end) of
        {ok, _} -> ok;
        Error -> Error
    end.

%% @doc Delete a relationship.
-spec delete_relationship(mri(), predicate(), mri()) -> ok | {error, term()}.
delete_relationship(Subject, Predicate, Object) ->
    delete_relationship(?DEFAULT_STORE, Subject, Predicate, Object).

-spec delete_relationship(store(), mri(), predicate(), mri()) -> ok | {error, term()}.
delete_relationship(Store, Subject, Predicate, Object) ->
    ForwardPath = [mri_rel, forward, Subject, Predicate, Object],
    ReversePath = [mri_rel, reverse, Object, Predicate, Subject],

    %% khepri:transaction returns {ok, TransactionResult} or {error, ...}
    case khepri:transaction(Store, fun() ->
        khepri_tx:delete(ForwardPath),
        khepri_tx:delete(ReversePath)
    end) of
        {ok, _} -> ok;
        Error -> Error
    end.

%% @doc Check if a relationship exists.
-spec relationship_exists(mri(), predicate(), mri()) -> boolean().
relationship_exists(Subject, Predicate, Object) ->
    relationship_exists(?DEFAULT_STORE, Subject, Predicate, Object).

-spec relationship_exists(store(), mri(), predicate(), mri()) -> boolean().
relationship_exists(Store, Subject, Predicate, Object) ->
    Path = [mri_rel, forward, Subject, Predicate, Object],
    khepri:exists(Store, Path).

%% @doc Get a relationship with its metadata.
-spec get_relationship(mri(), predicate(), mri()) -> {ok, map()} | {error, not_found | term()}.
get_relationship(Subject, Predicate, Object) ->
    get_relationship(?DEFAULT_STORE, Subject, Predicate, Object).

-spec get_relationship(store(), mri(), predicate(), mri()) -> {ok, map()} | {error, not_found | term()}.
get_relationship(Store, Subject, Predicate, Object) ->
    Path = [mri_rel, forward, Subject, Predicate, Object],
    case khepri:get(Store, Path) of
        {ok, Value} when is_map(Value) ->
            {ok, Value};
        {error, {khepri, node_not_found, _}} ->
            {error, not_found};
        {error, {node_not_found, _}} ->
            {error, not_found};
        Error ->
            Error
    end.

%%====================================================================
%% Forward Queries (Subject -> Objects)
%%====================================================================

%% @doc Get all objects related to subject via predicate.
-spec related_to(mri(), predicate()) -> [mri()].
related_to(Subject, Predicate) ->
    related_to(?DEFAULT_STORE, Subject, Predicate).

-spec related_to(store(), mri(), predicate()) -> [mri()].
related_to(Store, Subject, Predicate) ->
    Path = [mri_rel, forward, Subject, Predicate, #if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [maps:get(object, V) || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%% @doc Get all relationships from a subject.
-spec all_related(mri()) -> [{predicate(), mri()}].
all_related(Subject) ->
    all_related(?DEFAULT_STORE, Subject).

-spec all_related(store(), mri()) -> [{predicate(), mri()}].
all_related(Store, Subject) ->
    Path = [mri_rel, forward, Subject, #if_name_matches{regex = any}, #if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [{maps:get(predicate, V), maps:get(object, V)}
             || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%%====================================================================
%% Reverse Queries (Object -> Subjects)
%%====================================================================

%% @doc Get all subjects related to object via predicate.
-spec related_from(mri(), predicate()) -> [mri()].
related_from(Object, Predicate) ->
    related_from(?DEFAULT_STORE, Object, Predicate).

-spec related_from(store(), mri(), predicate()) -> [mri()].
related_from(Store, Object, Predicate) ->
    Path = [mri_rel, reverse, Object, Predicate, #if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [maps:get(subject, V) || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%% @doc Get all relationships to an object.
-spec all_related_from(mri()) -> [{predicate(), mri()}].
all_related_from(Object) ->
    all_related_from(?DEFAULT_STORE, Object).

-spec all_related_from(store(), mri()) -> [{predicate(), mri()}].
all_related_from(Store, Object) ->
    Path = [mri_rel, reverse, Object, #if_name_matches{regex = any}, #if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [{maps:get(predicate, V), maps:get(subject, V)}
             || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%%====================================================================
%% Graph Traversal (Backwards Compatible)
%%====================================================================

%% @doc Traverse one hop in the given direction.
-spec traverse(mri(), predicate(), direction()) -> [mri()].
traverse(Start, Predicate, Direction) ->
    traverse(?DEFAULT_STORE, Start, Predicate, Direction).

-spec traverse(store(), mri(), predicate(), direction()) -> [mri()].
traverse(Store, Start, Predicate, forward) ->
    related_to(Store, Start, Predicate);
traverse(Store, Start, Predicate, reverse) ->
    related_from(Store, Start, Predicate).

%% @doc Traverse transitively (follow all edges of type).
%% Uses default max_depth of 100.
-spec traverse_transitive(mri(), predicate(), direction()) -> [mri()].
traverse_transitive(Start, Predicate, Direction) ->
    traverse_transitive(?DEFAULT_STORE, Start, Predicate, Direction).

-spec traverse_transitive(store(), mri(), predicate(), direction()) -> [mri()].
traverse_transitive(Store, Start, Predicate, Direction) ->
    traverse_transitive_opts(Store, Start, Predicate, Direction, #{}).

%%====================================================================
%% Graph Traversal with Options
%%====================================================================

%% @doc Traverse transitively with options.
%%
%% Options:
%% - `max_depth': Maximum traversal depth (default: 100)
%%
%% Example:
%% ```
%% traverse_transitive_opts(Start, depends_on, forward, #{max_depth => 5})
%% '''
-spec traverse_transitive_opts(mri(), predicate(), direction(), traverse_opts()) -> [mri()].
traverse_transitive_opts(Start, Predicate, Direction, Opts) ->
    traverse_transitive_opts(?DEFAULT_STORE, Start, Predicate, Direction, Opts).

-spec traverse_transitive_opts(store(), mri(), predicate(), direction(), traverse_opts()) -> [mri()].
traverse_transitive_opts(Store, Start, Predicate, Direction, Opts) ->
    MaxDepth = maps:get(max_depth, Opts, ?DEFAULT_MAX_DEPTH),
    traverse_transitive_acc(Store, Start, Predicate, Direction, sets:new(), 0, MaxDepth).

%% @private Recursive traversal with depth tracking.
traverse_transitive_acc(_Store, _Current, _Predicate, _Direction, _Visited, Depth, MaxDepth) when Depth >= MaxDepth ->
    %% Max depth reached, stop traversal
    [];
traverse_transitive_acc(Store, Current, Predicate, Direction, Visited, Depth, MaxDepth) ->
    case sets:is_element(Current, Visited) of
        true ->
            [];
        false ->
            NewVisited = sets:add_element(Current, Visited),
            DirectNeighbors = traverse(Store, Current, Predicate, Direction),
            %% Filter out already-visited neighbors to handle cycles correctly
            UnvisitedNeighbors = [N || N <- DirectNeighbors,
                                       not sets:is_element(N, NewVisited)],
            Transitive = lists:flatmap(fun(N) ->
                traverse_transitive_acc(Store, N, Predicate, Direction, NewVisited, Depth + 1, MaxDepth)
            end, UnvisitedNeighbors),
            UnvisitedNeighbors ++ Transitive
    end.

%%====================================================================
%% Taxonomy Helpers
%%====================================================================

%% @doc Get direct instances of a class.
-spec instances_of(mri()) -> [mri()].
instances_of(Class) ->
    instances_of(?DEFAULT_STORE, Class).

-spec instances_of(store(), mri()) -> [mri()].
instances_of(Store, Class) ->
    related_from(Store, Class, instance_of).

%% @doc Get all instances including subclasses (transitive).
-spec instances_of_transitive(mri()) -> [mri()].
instances_of_transitive(Class) ->
    instances_of_transitive(?DEFAULT_STORE, Class).

-spec instances_of_transitive(store(), mri()) -> [mri()].
instances_of_transitive(Store, Class) ->
    %% Direct instances
    Direct = instances_of(Store, Class),
    %% Instances of subclasses
    SubClasses = subclasses(Store, Class),
    Indirect = lists:flatmap(fun(SC) ->
        instances_of_transitive(Store, SC)
    end, SubClasses),
    lists:usort(Direct ++ Indirect).

%% @doc Get classes of an instance.
-spec classes_of(mri()) -> [mri()].
classes_of(Instance) ->
    classes_of(?DEFAULT_STORE, Instance).

-spec classes_of(store(), mri()) -> [mri()].
classes_of(Store, Instance) ->
    related_to(Store, Instance, instance_of).

%% @doc Get direct subclasses of a class.
-spec subclasses(mri()) -> [mri()].
subclasses(Class) ->
    subclasses(?DEFAULT_STORE, Class).

-spec subclasses(store(), mri()) -> [mri()].
subclasses(Store, Class) ->
    related_from(Store, Class, subclass_of).

%% @doc Get direct superclasses of a class.
-spec superclasses(mri()) -> [mri()].
superclasses(Class) ->
    superclasses(?DEFAULT_STORE, Class).

-spec superclasses(store(), mri()) -> [mri()].
superclasses(Store, Class) ->
    related_to(Store, Class, subclass_of).
