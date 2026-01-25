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

    %% Tree queries
    list_children/1,
    list_children/2,
    list_descendants/1,
    list_descendants/2,
    list_by_type/2,
    list_by_type/3,
    count_children/1,
    count_children/2,

    %% Bulk operations
    import/1,
    import/2,
    export_subtree/1,
    export_subtree/2
]).

-define(DEFAULT_STORE, mri_store).

-include_lib("khepri/include/khepri.hrl").

%%====================================================================
%% Types
%%====================================================================

-type mri() :: binary().
-type metadata() :: map().
-type store() :: atom().

%%====================================================================
%% CRUD Operations
%%====================================================================

%% @doc Register a new MRI with metadata.
-spec register(mri(), metadata()) -> ok | {error, term()}.
register(MRI, Metadata) ->
    register(?DEFAULT_STORE, MRI, Metadata).

-spec register(store(), mri(), metadata()) -> ok | {error, term()}.
register(Store, MRI, Metadata) ->
    Path = mri_to_path(MRI),
    Data = Metadata#{
        mri => MRI,
        registered_at => erlang:system_time(millisecond)
    },
    case khepri:create(Store, Path, Data) of
        ok ->
            update_indexes(Store, MRI, Metadata),
            ok;
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
    Path = mri_to_path(MRI),
    case khepri:get(Store, Path) of
        {ok, Value} -> {ok, Value};
        {error, {node_not_found, _}} -> {error, not_found};
        Error -> Error
    end.

%% @doc Update an existing MRI's metadata.
-spec update(mri(), metadata()) -> ok | {error, term()}.
update(MRI, Metadata) ->
    update(?DEFAULT_STORE, MRI, Metadata).

-spec update(store(), mri(), metadata()) -> ok | {error, term()}.
update(Store, MRI, Metadata) ->
    Path = mri_to_path(MRI),
    case khepri:get(Store, Path) of
        {ok, Existing} ->
            Updated = maps:merge(Existing, Metadata#{
                updated_at => erlang:system_time(millisecond)
            }),
            khepri:put(Store, Path, Updated);
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
    Path = mri_to_path(MRI),
    remove_indexes(Store, MRI),
    case khepri:delete(Store, Path) of
        ok -> ok;
        {error, {node_not_found, _}} -> {error, not_found};
        Error -> Error
    end.

%% @doc Check if an MRI exists.
-spec exists(mri()) -> boolean().
exists(MRI) ->
    exists(?DEFAULT_STORE, MRI).

-spec exists(store(), mri()) -> boolean().
exists(Store, MRI) ->
    Path = mri_to_path(MRI),
    khepri:exists(Store, Path).

%%====================================================================
%% Tree Queries
%%====================================================================

%% @doc List direct children of an MRI.
-spec list_children(mri()) -> [mri()].
list_children(MRI) ->
    do_list_children(?DEFAULT_STORE, MRI).

-spec list_children(store(), mri()) -> [mri()].
list_children(Store, MRI) ->
    do_list_children(Store, MRI).

do_list_children(Store, MRI) ->
    Path = mri_to_path(MRI) ++ [#if_name_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [maps:get(mri, V) || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%% @doc List all descendants of an MRI.
-spec list_descendants(mri()) -> [mri()].
list_descendants(MRI) ->
    do_list_descendants(?DEFAULT_STORE, MRI).

-spec list_descendants(store(), mri()) -> [mri()].
list_descendants(Store, MRI) ->
    do_list_descendants(Store, MRI).

do_list_descendants(Store, MRI) ->
    Path = mri_to_path(MRI) ++ [#if_path_matches{regex = any}],
    case khepri:get_many(Store, Path) of
        {ok, Results} ->
            [maps:get(mri, V) || {_, V} <- maps:to_list(Results), is_map(V)];
        _ ->
            []
    end.

%% @doc List all MRIs of a given type in a realm.
-spec list_by_type(atom(), binary()) -> [mri()].
list_by_type(Type, Realm) ->
    do_list_by_type(?DEFAULT_STORE, Type, Realm).

-spec list_by_type(store(), atom(), binary()) -> [mri()].
list_by_type(Store, Type, Realm) ->
    do_list_by_type(Store, Type, Realm).

do_list_by_type(Store, Type, Realm) ->
    %% Use type index if available
    IndexPath = [mri_index, by_type, Type, Realm, #if_path_matches{regex = any}],
    case khepri:get_many(Store, IndexPath) of
        {ok, Results} ->
            maps:keys(Results);
        _ ->
            %% Fallback to direct query
            Path = [mri, Type, Realm, #if_path_matches{regex = any}],
            case khepri:get_many(Store, Path) of
                {ok, Rs} ->
                    [maps:get(mri, V) || {_, V} <- maps:to_list(Rs), is_map(V)];
                _ ->
                    []
            end
    end.

%% @doc Count direct children of an MRI.
-spec count_children(mri()) -> non_neg_integer().
count_children(MRI) ->
    do_count_children(?DEFAULT_STORE, MRI).

-spec count_children(store(), mri()) -> non_neg_integer().
count_children(Store, MRI) ->
    do_count_children(Store, MRI).

do_count_children(Store, MRI) ->
    length(do_list_children(Store, MRI)).

%%====================================================================
%% Bulk Operations
%%====================================================================

%% @doc Import multiple MRIs with their metadata.
-spec import([{mri(), metadata()}]) -> ok | {error, term()}.
import(Entries) ->
    import(?DEFAULT_STORE, Entries).

-spec import(store(), [{mri(), metadata()}]) -> ok | {error, term()}.
import(Store, Entries) ->
    khepri:transaction(Store, fun() ->
        lists:foreach(fun({MRI, Metadata}) ->
            Path = mri_to_path(MRI),
            Data = Metadata#{mri => MRI, registered_at => erlang:system_time(millisecond)},
            khepri_tx:put(Path, Data)
        end, Entries)
    end).

%% @doc Export a subtree as a list of {MRI, Metadata} tuples.
-spec export_subtree(mri()) -> [{mri(), metadata()}].
export_subtree(MRI) ->
    do_export_subtree(?DEFAULT_STORE, MRI).

-spec export_subtree(store(), mri()) -> [{mri(), metadata()}].
export_subtree(Store, MRI) ->
    do_export_subtree(Store, MRI).

do_export_subtree(Store, MRI) ->
    Descendants = do_list_descendants(Store, MRI),
    lists:filtermap(fun(D) ->
        case lookup(Store, D) of
            {ok, Meta} -> {true, {D, Meta}};
            _ -> false
        end
    end, [MRI | Descendants]).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Convert an MRI to a Khepri path.
-spec mri_to_path(mri()) -> [atom() | binary()].
mri_to_path(MRI) ->
    case parse_mri(MRI) of
        {ok, Type, Realm, Segments} ->
            [mri, Type, Realm | Segments];
        {error, _} ->
            error({invalid_mri, MRI})
    end.

%% @private Parse an MRI into its components.
%% TODO: Use macula_mri:parse/1 when available
-spec parse_mri(mri()) -> {ok, atom(), binary(), [binary()]} | {error, term()}.
parse_mri(<<"mri:", Rest/binary>>) ->
    case binary:split(Rest, <<":">>) of
        [TypeBin, RealmPath] ->
            Type = binary_to_existing_atom(TypeBin, utf8),
            case binary:split(RealmPath, <<"/">>) of
                [Realm] ->
                    {ok, Type, Realm, []};
                [Realm | Segments] ->
                    %% Handle case where split returns [Realm, Rest]
                    AllSegments = case Segments of
                        [PathRest] -> binary:split(PathRest, <<"/">>, [global]);
                        Other -> Other
                    end,
                    {ok, Type, Realm, AllSegments}
            end;
        _ ->
            {error, invalid_format}
    end;
parse_mri(_) ->
    {error, invalid_prefix}.

%% @private Update secondary indexes for an MRI.
-spec update_indexes(store(), mri(), metadata()) -> ok.
update_indexes(Store, MRI, _Metadata) ->
    case parse_mri(MRI) of
        {ok, Type, Realm, _} ->
            %% Type index
            TypeIndexPath = [mri_index, by_type, Type, Realm, MRI],
            khepri:put(Store, TypeIndexPath, true),
            %% Realm index
            RealmIndexPath = [mri_index, by_realm, Realm, MRI],
            khepri:put(Store, RealmIndexPath, true),
            ok;
        _ ->
            ok
    end.

%% @private Remove secondary indexes for an MRI.
-spec remove_indexes(store(), mri()) -> ok.
remove_indexes(Store, MRI) ->
    case parse_mri(MRI) of
        {ok, Type, Realm, _} ->
            TypeIndexPath = [mri_index, by_type, Type, Realm, MRI],
            khepri:delete(Store, TypeIndexPath),
            RealmIndexPath = [mri_index, by_realm, Realm, MRI],
            khepri:delete(Store, RealmIndexPath),
            ok;
        _ ->
            ok
    end.
