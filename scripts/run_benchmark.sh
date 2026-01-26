#!/bin/bash
# Run Proximus benchmark demo
# Usage: ./scripts/run_benchmark.sh [scale]
# Default scale is 0.01 (1% = ~40 SRPs, ~10K homes)

SCALE="${1:-0.01}"
cd "$(dirname "$0")/.."

rebar3 shell --eval "
{ok, _} = application:ensure_all_started(ra),
{ok, _} = application:ensure_all_started(khepri),

TempDir = \"/tmp/macula_benchmark_\" ++ integer_to_list(erlang:unique_integer([positive])),
filelib:ensure_dir(TempDir ++ \"/\"),

RaConfig = #{name => bench, data_dir => TempDir, wal_data_dir => TempDir, names => ra_system:derive_names(bench)},
{ok, _} = ra_system:start(RaConfig),
{ok, _} = khepri:start(bench, bench),
ok = khepri:fence(bench, 10000),

lists:foreach(fun(P) -> khepri:put(bench, P, #{}) end, [[mri_index, by_type], [mri_index, by_realm], [mri_rel, forward], [mri_rel, reverse]]),

macula_mri_khepri_proximus_demo:benchmark(bench, #{scale => ${SCALE}, iterations => 50}),

khepri:stop(bench),
ra_system:stop(bench),
os:cmd(\"rm -rf \" ++ TempDir),
init:stop().
"
