%%%-------------------------------------------------------------------
%%% @doc
%%% Index manager for MRI Khepri storage.
%%%
%%% Ensures secondary indexes are properly initialized and maintained.
%%% Runs as a GenServer that initializes after Khepri starts.
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_index).

-behaviour(gen_server).

-export([start_link/1]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-export([
    rebuild_indexes/0,
    rebuild_indexes/1
]).

-define(SERVER, ?MODULE).

-include_lib("khepri/include/khepri.hrl").

-record(state, {
    store :: atom()
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(StoreName) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [StoreName], []).

%% @doc Rebuild all indexes (useful after data import or corruption).
-spec rebuild_indexes() -> ok.
rebuild_indexes() ->
    rebuild_indexes(mri_store).

-spec rebuild_indexes(atom()) -> ok.
rebuild_indexes(Store) ->
    gen_server:call(?SERVER, {rebuild_indexes, Store}, infinity).

%%====================================================================
%% GenServer Callbacks
%%====================================================================

init([StoreName]) ->
    %% Initialize indexes after a short delay to ensure Khepri is ready
    self() ! initialize_indexes,
    {ok, #state{store = StoreName}}.

handle_call({rebuild_indexes, Store}, _From, State) ->
    do_rebuild_indexes(Store),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(initialize_indexes, #state{store = Store} = State) ->
    ensure_index_structure(Store),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Ensure the index tree structure exists.
%%
%% Note: Khepri automatically creates intermediate paths when writing,
%% so explicit root node initialization is not strictly necessary.
%% This function is kept as a no-op for backwards compatibility and
%% to document the expected index structure.
ensure_index_structure(_Store) ->
    %% Index paths:
    %% - [mri_index, by_type, Type, Realm, MRI] -> true
    %% - [mri_index, by_realm, Realm, MRI] -> true
    %% - [mri_rel, forward, Subject, Predicate, Object] -> Metadata
    %% - [mri_rel, reverse, Object, Predicate, Subject] -> Metadata
    %%
    %% These paths are created on-demand by Khepri when indexes are written.
    %% No initialization needed.
    ok.

%% @private Rebuild all indexes from stored MRIs.
do_rebuild_indexes(Store) ->
    %% Clear existing indexes
    khepri:delete(Store, [mri_index]),

    %% Scan all MRIs and rebuild indexes
    %% This is expensive but necessary for recovery
    scan_and_index(Store, [mri]).

scan_and_index(Store, BasePath) ->
    case khepri:get_many(Store, BasePath ++ ['_']) of
        {ok, Results} ->
            maps:foreach(fun(Path, Value) when is_map(Value) ->
                case maps:get(mri, Value, undefined) of
                    undefined -> ok;
                    MRI -> index_mri(Store, MRI, Value)
                end,
                %% Recurse into children
                scan_and_index(Store, Path);
            (_, _) ->
                ok
            end, Results);
        _ ->
            ok
    end.

index_mri(Store, MRI, Metadata) ->
    case macula_mri_khepri_parse:parse(MRI) of
        {ok, Type, Realm, _} ->
            %% Type index (config-driven)
            case application:get_env(macula_mri_khepri, enable_type_index, true) of
                true ->
                    TypePath = [mri_index, by_type, Type, Realm, MRI],
                    khepri:put(Store, TypePath, true);
                false ->
                    ok
            end,
            %% Realm index (config-driven)
            case application:get_env(macula_mri_khepri, enable_realm_index, true) of
                true ->
                    RealmPath = [mri_index, by_realm, Realm, MRI],
                    khepri:put(Store, RealmPath, true);
                false ->
                    ok
            end,
            %% Custom indexes from metadata
            index_custom(Store, MRI, Metadata);
        _ ->
            ok
    end.

index_custom(_Store, _MRI, _Metadata) ->
    %% Placeholder for custom index logic
    %% Users can extend this via configuration
    ok.
