%%%-------------------------------------------------------------------
%%% @doc
%%% Macula MRI Khepri application module.
%%%
%%% Starts the Khepri-based persistence layer for Macula Resource
%%% Identifiers (MRI). Provides distributed, Raft-consensus storage
%%% for MRI registration and graph relationships.
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    macula_mri_khepri_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
