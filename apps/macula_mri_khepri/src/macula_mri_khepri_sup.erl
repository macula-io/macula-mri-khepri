%%%-------------------------------------------------------------------
%%% @doc
%%% Macula MRI Khepri top-level supervisor.
%%%
%%% Manages the Khepri store lifecycle and index workers.
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% @doc Start the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc Initialize the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },

    %% Get configuration
    StoreName = application:get_env(macula_mri_khepri, store_name, mri_store),
    DataDir = application:get_env(macula_mri_khepri, data_dir, "/tmp/macula_mri"),

    %% Khepri store child spec
    KhepriSpec = #{
        id => khepri_store,
        start => {khepri, start, [StoreName, #{data_dir => DataDir}]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [khepri]
    },

    %% Index manager (ensures indexes exist after Khepri starts)
    IndexSpec = #{
        id => mri_index_manager,
        start => {macula_mri_khepri_index, start_link, [StoreName]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [macula_mri_khepri_index]
    },

    {ok, {SupFlags, [KhepriSpec, IndexSpec]}}.
