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
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_graph).

%% TODO: Implement behaviour when macula_mri is released
%% -behaviour(macula_mri_graph).

-export([
    %% Relationship CRUD
    create_relationship/3,
    create_relationship/4,
    create_relationship/5,
    delete_relationship/3,
    delete_relationship/4,
    relationship_exists/3,
    relationship_exists/4,

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

    %% Graph traversal
    traverse/3,
    traverse/4,
    traverse_transitive/3,
    traverse_transitive/4,

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

-include_lib("khepri/include/khepri.hrl").

%%====================================================================
%% Types
%%====================================================================

-type mri() :: binary().
-type predicate() :: atom() | {custom, binary()}.
-type metadata() :: map().
-type store() :: atom().
-type direction() :: forward | reverse.

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

    khepri:transaction(Store, fun() ->
        khepri_tx:put(ForwardPath, Data),
        khepri_tx:put(ReversePath, Data)
    end).

%% @doc Delete a relationship.
-spec delete_relationship(mri(), predicate(), mri()) -> ok | {error, term()}.
delete_relationship(Subject, Predicate, Object) ->
    delete_relationship(?DEFAULT_STORE, Subject, Predicate, Object).

-spec delete_relationship(store(), mri(), predicate(), mri()) -> ok | {error, term()}.
delete_relationship(Store, Subject, Predicate, Object) ->
    ForwardPath = [mri_rel, forward, Subject, Predicate, Object],
    ReversePath = [mri_rel, reverse, Object, Predicate, Subject],

    khepri:transaction(Store, fun() ->
        khepri_tx:delete(ForwardPath),
        khepri_tx:delete(ReversePath)
    end).

%% @doc Check if a relationship exists.
-spec relationship_exists(mri(), predicate(), mri()) -> boolean().
relationship_exists(Subject, Predicate, Object) ->
    relationship_exists(?DEFAULT_STORE, Subject, Predicate, Object).

-spec relationship_exists(store(), mri(), predicate(), mri()) -> boolean().
relationship_exists(Store, Subject, Predicate, Object) ->
    Path = [mri_rel, forward, Subject, Predicate, Object],
    khepri:exists(Store, Path).

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
%% Graph Traversal
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
-spec traverse_transitive(mri(), predicate(), direction()) -> [mri()].
traverse_transitive(Start, Predicate, Direction) ->
    traverse_transitive(?DEFAULT_STORE, Start, Predicate, Direction).

-spec traverse_transitive(store(), mri(), predicate(), direction()) -> [mri()].
traverse_transitive(Store, Start, Predicate, Direction) ->
    traverse_transitive_acc(Store, Start, Predicate, Direction, sets:new()).

traverse_transitive_acc(Store, Current, Predicate, Direction, Visited) ->
    case sets:is_element(Current, Visited) of
        true ->
            [];
        false ->
            NewVisited = sets:add_element(Current, Visited),
            DirectNeighbors = traverse(Store, Current, Predicate, Direction),
            Transitive = lists:flatmap(fun(N) ->
                traverse_transitive_acc(Store, N, Predicate, Direction, NewVisited)
            end, DirectNeighbors),
            DirectNeighbors ++ Transitive
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
