#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa _build/default/lib/*/ebin -sname mri_demo

main(_Args) ->
    %% Start required applications
    ok = application:start(crypto),
    ok = application:start(asn1),
    ok = application:start(public_key),
    ok = application:start(ssl),
    {ok, _} = application:ensure_all_started(ra),
    {ok, _} = application:ensure_all_started(khepri),

    %% Run the TUI
    macula_mri_khepri_tui:start().
