#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa _build/default/lib/*/ebin -sname benchmark_runner

main([]) ->
    main(["0.005"]);
main([ScaleStr]) ->
    Scale = list_to_float(ScaleStr),

    %% Start applications
    {ok, _} = application:ensure_all_started(ra),
    {ok, _} = application:ensure_all_started(khepri),

    %% Create temp directory
    TempDir = "/tmp/macula_mri_benchmark_" ++ integer_to_list(erlang:unique_integer([positive])),
    filelib:ensure_dir(TempDir ++ "/"),

    %% Start Ra system
    RaConfig = #{
        name => benchmark_store,
        data_dir => TempDir,
        wal_data_dir => TempDir,
        names => ra_system:derive_names(benchmark_store)
    },
    {ok, _} = ra_system:start(RaConfig),

    %% Start Khepri store
    {ok, _} = khepri:start(benchmark_store, benchmark_store),
    ok = khepri:fence(benchmark_store, 10000),

    %% Initialize index structure
    lists:foreach(fun(Path) ->
        khepri:put(benchmark_store, Path, #{initialized => true})
    end, [
        [mri_index, by_type],
        [mri_index, by_realm],
        [mri_rel, forward],
        [mri_rel, reverse]
    ]),

    %% Run benchmark
    io:format("Running benchmark at ~p scale...~n~n", [Scale]),
    macula_mri_khepri_proximus_demo:benchmark(benchmark_store, #{
        scale => Scale,
        iterations => 50
    }),

    %% Cleanup
    khepri:stop(benchmark_store),
    ra_system:stop(benchmark_store),
    timer:sleep(200),
    os:cmd("rm -rf " ++ TempDir),

    io:format("~nBenchmark complete!~n").
