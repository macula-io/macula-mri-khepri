%%%-------------------------------------------------------------------
%%% @doc
%%% Khepri-based storage adapter for Macula Resource Identifiers.
%%%
%%% Implements the macula_mri_store behaviour using Khepri's tree-based
%%% storage with Raft consensus for distributed consistency.
%%%
%%% == Storage Schema ==
%%%
%%% MRIs are stored at paths that mirror their structure:
%%% ```
%%% [mri, Type, Realm, Segment1, Segment2, ...]
%%% '''
%%%
%%% Example:
%%% ```
%%% mri:app:io.macula/acme/counter
%%% -> [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>]
%%% '''
%%%
%%% == Pagination ==
%%%
%%% List functions support optional pagination via an options map:
%%% ```
%%% #{limit => 100, offset => 0}
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_store).

%% TODO: Implement behaviour when macula_mri is released
%% -behaviour(macula_mri_store).

-export([
    %% CRUD operations
    register/2,
    register/3,
    lookup/1,
    lookup/2,
    update/2,
    update/3,
    delete/1,
    delete/2,
    exists/1,
    exists/2,

    %% Tree queries (without pagination - backwards compatible)
    list_children/1,
    list_children/2,
    list_descendants/1,
    list_descendants/2,
    list_by_type/2,
    list_by_type/3,
    count_children/1,
    count_children/2,

    %% Tree queries with pagination options
    list_children_opts/2,
    list_children_opts/3,
    list_descendants_opts/2,
    list_descendants_opts/3,
    list_by_type_opts/3,
    list_by_type_opts/4,

    %% Bulk operations
    import/1,
    import/2,
    export_subtree/1,
    export_subtree/2
]).

-define(DEFAULT_STORE, mri_store).
-define(DEFAULT_LIMIT, 1000).
-define(DEFAULT_OFFSET, 0).

-include_lib("khepri/include/khepri.hrl").
-include_lib("kernel/include/logger.hrl").

%%====================================================================
%% Types
%%====================================================================

-type mri() :: binary().
-type metadata() :: map().
-type store() :: atom().
-type pagination_opts() :: #{
    limit => pos_integer(),
    offset => non_neg_integer()
}.

%%====================================================================
%% CRUD Operations
%%====================================================================

%% @doc Register a new MRI with metadata.
-spec register(mri(), metadata()) -> ok | {error, term()}.
register(MRI, Metadata) ->
    register(?DEFAULT_STORE, MRI, Metadata).

-spec register(store(), mri(), metadata()) -> ok | {error, term()}.
register(Store, MRI, Metadata) ->
    Path = macula_mri_khepri_parse:to_path(MRI),
    Data = Metadata#{
        mri => MRI,
        registered_at => erlang:system_time(millisecond)
    },
    case khepri:create(Store, Path, Data) of
        ok ->
            update_indexes(Store, MRI, Metadata),
            ok;
        %% Khepri 0.16+ uses {error, {khepri, mismatching_node, ...}} format
        {error, {khepri, mismatching_node, _}} ->
            {error, already_exists};
        %% Legacy format for backwards compatibility
        {error, {mismatching_node, _}} ->
            {error, already_exists};
        Error ->
            Error
    end.

%% @doc Look up an MRI's metadata.
-spec lookup(mri()) -> {ok, metadata()} | {error, not_found}.
lookup(MRI) ->
    lookup(?DEFAULT_STORE, MRI).

-spec lookup(store(), mri()) -> {ok, metadata()} | {error, not_found}.
lookup(Store, MRI) ->
    Path = macula_mri_khepri_parse:to_path(MRI),
    case khepri:get(Store, Path) of
        {ok, Value} -> {ok, Value};
        %% Khepri 0.16+ error format
        {error, {khepri, node_not_found, _}} -> {error, not_found};
        %% Legacy format
        {error, {node_not_found, _}} -> {error, not_found};
        Error -> Error
    end.

%% @doc Update an existing MRI's metadata.
-spec update(mri(), metadata()) -> ok | {error, term()}.
update(MRI, Metadata) ->
    update(?DEFAULT_STORE, MRI, Metadata).

-spec update(store(), mri(), metadata()) -> ok | {error, term()}.
update(Store, MRI, Metadata) ->
    Path = macula_mri_khepri_parse:to_path(MRI),
    case khepri:get(Store, Path) of
        {ok, Existing} ->
            Updated = maps:merge(Existing, Metadata#{
                updated_at => erlang:system_time(millisecond)
            }),
            khepri:put(Store, Path, Updated);
        %% Khepri 0.16+ error format
        {error, {khepri, node_not_found, _}} ->
            {error, not_found};
        %% Legacy format
        {error, {node_not_found, _}} ->
            {error, not_found};
        Error ->
            Error
    end.

%% @doc Delete an MRI.
-spec delete(mri()) -> ok | {error, term()}.
delete(MRI) ->
    delete(?DEFAULT_STORE, MRI).

-spec delete(store(), mri()) -> ok | {error, term()}.
delete(Store, MRI) ->
    Path = macula_mri_khepri_parse:to_path(MRI),
    remove_indexes(Store, MRI),
    case khepri:delete(Store, Path) of
        ok -> ok;
        %% Khepri 0.16+ error format
        {error, {khepri, node_not_found, _}} -> {error, not_found};
        %% Legacy format
        {error, {node_not_found, _}} -> {error, not_found};
        Error -> Error
    end.

%% @doc Check if an MRI exists.
-spec exists(mri()) -> boolean().
exists(MRI) ->
    exists(?DEFAULT_STORE, MRI).

-spec exists(store(), mri()) -> boolean().
exists(Store, MRI) ->
    Path = macula_mri_khepri_parse:to_path(MRI),
    khepri:exists(Store, Path).

%%====================================================================
%% Tree Queries (Backwards Compatible - No Pagination)
%%====================================================================

%% @doc List direct children of an MRI.
-spec list_children(mri()) -> [mri()].
list_children(MRI) ->
    do_list_children(?DEFAULT_STORE, MRI, default_opts()).

-spec list_children(store(), mri()) -> [mri()].
list_children(Store, MRI) ->
    do_list_children(Store, MRI, default_opts()).

%% @doc List all descendants of an MRI.
-spec list_descendants(mri()) -> [mri()].
list_descendants(MRI) ->
    do_list_descendants(?DEFAULT_STORE, MRI, default_opts()).

-spec list_descendants(store(), mri()) -> [mri()].
list_descendants(Store, MRI) ->
    do_list_descendants(Store, MRI, default_opts()).

%% @doc List all MRIs of a given type in a realm.
-spec list_by_type(atom(), binary()) -> [mri()].
list_by_type(Type, Realm) ->
    do_list_by_type(?DEFAULT_STORE, Type, Realm, default_opts()).

-spec list_by_type(store(), atom(), binary()) -> [mri()].
list_by_type(Store, Type, Realm) ->
    do_list_by_type(Store, Type, Realm, default_opts()).

%% @doc Count direct children of an MRI.
-spec count_children(mri()) -> non_neg_integer().
count_children(MRI) ->
    do_count_children(?DEFAULT_STORE, MRI).

-spec count_children(store(), mri()) -> non_neg_integer().
count_children(Store, MRI) ->
    do_count_children(Store, MRI).

%%====================================================================
%% Tree Queries with Pagination Options
%%====================================================================

%% @doc List direct children of an MRI with pagination.
%%
%% Options:
%% - `limit': Maximum number of results (default: 1000)
%% - `offset': Number of results to skip (default: 0)
-spec list_children_opts(mri(), pagination_opts()) -> [mri()].
list_children_opts(MRI, Opts) ->
    do_list_children(?DEFAULT_STORE, MRI, merge_opts(Opts)).

-spec list_children_opts(store(), mri(), pagination_opts()) -> [mri()].
list_children_opts(Store, MRI, Opts) ->
    do_list_children(Store, MRI, merge_opts(Opts)).

%% @doc List all descendants of an MRI with pagination.
%%
%% Options:
%% - `limit': Maximum number of results (default: 1000)
%% - `offset': Number of results to skip (default: 0)
-spec list_descendants_opts(mri(), pagination_opts()) -> [mri()].
list_descendants_opts(MRI, Opts) ->
    do_list_descendants(?DEFAULT_STORE, MRI, merge_opts(Opts)).

-spec list_descendants_opts(store(), mri(), pagination_opts()) -> [mri()].
list_descendants_opts(Store, MRI, Opts) ->
    do_list_descendants(Store, MRI, merge_opts(Opts)).

%% @doc List all MRIs of a given type in a realm with pagination.
%%
%% Options:
%% - `limit': Maximum number of results (default: 1000)
%% - `offset': Number of results to skip (default: 0)
-spec list_by_type_opts(atom(), binary(), pagination_opts()) -> [mri()].
list_by_type_opts(Type, Realm, Opts) ->
    do_list_by_type(?DEFAULT_STORE, Type, Realm, merge_opts(Opts)).

-spec list_by_type_opts(store(), atom(), binary(), pagination_opts()) -> [mri()].
list_by_type_opts(Store, Type, Realm, Opts) ->
    do_list_by_type(Store, Type, Realm, merge_opts(Opts)).

%%====================================================================
%% Internal List Functions with Pagination
%%====================================================================

do_list_children(Store, MRI, Opts) ->
    Path = macula_mri_khepri_parse:to_path(MRI) ++ [#if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            MRIs = [maps:get(mri, V) || {_, V} <- maps:to_list(Results), is_map(V)],
            apply_pagination(MRIs, Opts);
        _ ->
            []
    end.

do_list_descendants(Store, MRI, Opts) ->
    Path = macula_mri_khepri_parse:to_path(MRI) ++ [#if_path_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            MRIs = [maps:get(mri, V) || {_, V} <- maps:to_list(Results), is_map(V)],
            apply_pagination(MRIs, Opts);
        _ ->
            []
    end.

do_list_by_type(Store, Type, Realm, Opts) ->
    %% Use type index if available
    %% Index path: [mri_index, by_type, Type, Realm, MRI] -> true
    IndexPath = [mri_index, by_type, Type, Realm, #if_path_matches{regex = any}],
    case khepri:get_many(Store, IndexPath) of
        {ok, Results} when map_size(Results) > 0 ->
            %% Keys are full paths; extract the MRI (last element)
            %% Handle both real Khepri (keys are paths) and mocked (keys may be binaries)
            MRIs = [extract_mri_from_key(Key) || Key <- maps:keys(Results)],
            apply_pagination(MRIs, Opts);
        _ ->
            %% Log warning about index miss and fallback
            ?LOG_WARNING("[macula_mri_khepri] Type index miss for ~p/~p, falling back to tree scan",
                        [Type, Realm]),
            %% Fallback to direct query
            Path = [mri, Type, Realm, #if_path_matches{regex = any}],
            case khepri:get_many(Store, Path) of
                {ok, Rs} ->
                    MRIs = [maps:get(mri, V) || {_, V} <- maps:to_list(Rs), is_map(V)],
                    apply_pagination(MRIs, Opts);
                _ ->
                    []
            end
    end.

do_count_children(Store, MRI) ->
    %% For count, we get all children (no pagination)
    length(do_list_children(Store, MRI, #{limit => infinity, offset => 0})).

%% @private Extract MRI from a key (handles both path lists and direct binaries)
extract_mri_from_key(Key) when is_list(Key) -> lists:last(Key);
extract_mri_from_key(Key) when is_binary(Key) -> Key.

%%====================================================================
%% Pagination Helpers
%%====================================================================

default_opts() ->
    #{limit => ?DEFAULT_LIMIT, offset => ?DEFAULT_OFFSET}.

merge_opts(Opts) ->
    maps:merge(default_opts(), Opts).

apply_pagination(List, #{limit := infinity}) ->
    List;
apply_pagination(List, #{limit := Limit, offset := Offset}) ->
    %% Apply offset and limit
    lists:sublist(lists:nthtail(min(Offset, length(List)), List), Limit).

%%====================================================================
%% Bulk Operations
%%====================================================================

%% @doc Import multiple MRIs with their metadata.
-spec import([{mri(), metadata()}]) -> ok | {error, term()}.
import(Entries) ->
    import(?DEFAULT_STORE, Entries).

-spec import(store(), [{mri(), metadata()}]) -> ok | {error, term()}.
import(Store, Entries) ->
    %% Prepare all entries with timestamps BEFORE the transaction
    %% (Khepri/Horus doesn't allow erlang:system_time in transactions)
    Now = erlang:system_time(millisecond),
    PreparedEntries = [{MRI, Metadata, macula_mri_khepri_parse:to_path(MRI)} || {MRI, Metadata} <- Entries],

    %% khepri:transaction returns {ok, TransactionResult} or {error, ...}
    case khepri:transaction(Store, fun() ->
        lists:foreach(fun({MRI, Metadata, Path}) ->
            Data = Metadata#{mri => MRI, registered_at => Now},
            khepri_tx:put(Path, Data)
        end, PreparedEntries)
    end) of
        {ok, _} -> ok;
        Error -> Error
    end.

%% @doc Export a subtree as a list of {MRI, Metadata} tuples.
-spec export_subtree(mri()) -> [{mri(), metadata()}].
export_subtree(MRI) ->
    do_export_subtree(?DEFAULT_STORE, MRI).

-spec export_subtree(store(), mri()) -> [{mri(), metadata()}].
export_subtree(Store, MRI) ->
    do_export_subtree(Store, MRI).

do_export_subtree(Store, MRI) ->
    Descendants = do_list_descendants(Store, MRI, #{limit => infinity, offset => 0}),
    lists:filtermap(fun(D) ->
        case lookup(Store, D) of
            {ok, Meta} -> {true, {D, Meta}};
            _ -> false
        end
    end, [MRI | Descendants]).

%%====================================================================
%% Index Functions (Config-Driven)
%%====================================================================

%% @private Update secondary indexes for an MRI.
-spec update_indexes(store(), mri(), metadata()) -> ok.
update_indexes(Store, MRI, _Metadata) ->
    case macula_mri_khepri_parse:parse(MRI) of
        {ok, Type, Realm, _} ->
            %% Type index (config-driven)
            case application:get_env(macula_mri_khepri, enable_type_index, true) of
                true ->
                    TypeIndexPath = [mri_index, by_type, Type, Realm, MRI],
                    khepri:put(Store, TypeIndexPath, true);
                false ->
                    ok
            end,
            %% Realm index (config-driven)
            case application:get_env(macula_mri_khepri, enable_realm_index, true) of
                true ->
                    RealmIndexPath = [mri_index, by_realm, Realm, MRI],
                    khepri:put(Store, RealmIndexPath, true);
                false ->
                    ok
            end,
            ok;
        _ ->
            ok
    end.

%% @private Remove secondary indexes for an MRI.
-spec remove_indexes(store(), mri()) -> ok.
remove_indexes(Store, MRI) ->
    case macula_mri_khepri_parse:parse(MRI) of
        {ok, Type, Realm, _} ->
            %% Type index (config-driven)
            case application:get_env(macula_mri_khepri, enable_type_index, true) of
                true ->
                    TypeIndexPath = [mri_index, by_type, Type, Realm, MRI],
                    khepri:delete(Store, TypeIndexPath);
                false ->
                    ok
            end,
            %% Realm index (config-driven)
            case application:get_env(macula_mri_khepri, enable_realm_index, true) of
                true ->
                    RealmIndexPath = [mri_index, by_realm, Realm, MRI],
                    khepri:delete(Store, RealmIndexPath);
                false ->
                    ok
            end,
            ok;
        _ ->
            ok
    end.
