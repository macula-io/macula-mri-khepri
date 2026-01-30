%%%-------------------------------------------------------------------
%%% @doc
%%% TelcoX-scale demo for Macula Resource Identifiers.
%%%
%%% Demonstrates the trie index performance with a realistic Belgian
%%% telecom network structure:
%%%
%%% - ~4000 street cabinets (SRPs - Street Remote Points)
%%% - ~250 homes per cabinet average
%%% - ~1M total home endpoints
%%%
%%% == Network Structure ==
%%%
%%% ```
%%% Realm: be.telcox
%%%
%%% Street Cabinets (SRPs):
%%%   mri:srp:be.telcox/{region}/{srp_id}
%%%
%%% Home Connections:
%%%   mri:home:be.telcox/{region}/{srp_id}/{home_id}
%%% '''
%%%
%%% == Regions ==
%%%
%%% Belgium is divided into regions:
%%% - brussels (Brussels Capital Region)
%%% - flanders (Flemish Region)
%%% - wallonia (Walloon Region)
%%%
%%% Each region contains multiple SRPs, each serving multiple homes.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_telcox_demo).

-include_lib("khepri/include/khepri.hrl").

-export([
    %% Demo lifecycle
    generate_network/1,
    generate_network/2,
    cleanup_network/1,
    cleanup_network/2,

    %% Query demos
    count_by_region/1,
    count_by_region/2,
    list_srps_in_region/2,
    list_srps_in_region/3,
    list_homes_for_srp/2,
    list_homes_for_srp/3,

    %% Benchmark
    benchmark/1,
    benchmark/2
]).

-define(DEFAULT_STORE, mri_store).
-define(REALM, <<"be.telcox">>).

%% Belgian regions with SRP distribution
-define(REGIONS, [
    {<<"brussels">>, 400},   %% 400 SRPs in Brussels
    {<<"flanders">>, 2200},  %% 2200 SRPs in Flanders
    {<<"wallonia">>, 1400}   %% 1400 SRPs in Wallonia
]).

%% Average homes per SRP (with variance)
-define(AVG_HOMES_PER_SRP, 250).
-define(HOMES_VARIANCE, 50).

%%====================================================================
%% Demo Lifecycle
%%====================================================================

%% @doc Generate a complete TelcoX-scale network.
%% Uses default batch size of 1000 for imports.
-spec generate_network(atom()) -> {ok, #{srps := non_neg_integer(), homes := non_neg_integer()}}.
generate_network(Store) ->
    generate_network(Store, #{batch_size => 1000}).

%% @doc Generate network with custom options.
%% Options:
%%   - batch_size: Number of MRIs to import per batch (default: 1000)
%%   - homes_per_srp: Override average homes per SRP
%%   - regions: Override region configuration [{Name, SrpCount}]
-spec generate_network(atom(), map()) -> {ok, #{srps := non_neg_integer(), homes := non_neg_integer()}}.
generate_network(Store, Opts) ->
    BatchSize = maps:get(batch_size, Opts, 1000),
    HomesPerSrp = maps:get(homes_per_srp, Opts, ?AVG_HOMES_PER_SRP),
    Variance = maps:get(homes_variance, Opts, ?HOMES_VARIANCE),
    Regions = maps:get(regions, Opts, ?REGIONS),

    io:format("Generating TelcoX network...~n"),
    io:format("  Regions: ~p~n", [length(Regions)]),

    %% Generate SRPs and homes region by region
    {TotalSrps, TotalHomes} = lists:foldl(
        fun({Region, SrpCount}, {SrpAcc, HomeAcc}) ->
            io:format("  Generating region ~s (~p SRPs)...~n", [Region, SrpCount]),
            {RegionSrps, RegionHomes} = generate_region(
                Store, Region, SrpCount, HomesPerSrp, Variance, BatchSize
            ),
            {SrpAcc + RegionSrps, HomeAcc + RegionHomes}
        end,
        {0, 0},
        Regions
    ),

    io:format("Network generated: ~p SRPs, ~p homes~n", [TotalSrps, TotalHomes]),
    {ok, #{srps => TotalSrps, homes => TotalHomes}}.

%% @private Generate a single region's SRPs and homes.
generate_region(Store, Region, SrpCount, AvgHomes, Variance, BatchSize) ->
    %% Generate SRP entries
    SrpEntries = [make_srp_entry(Region, N) || N <- lists:seq(1, SrpCount)],
    import_batched(Store, SrpEntries, BatchSize),

    %% Generate homes for each SRP
    HomeEntries = lists:flatmap(
        fun(N) ->
            HomeCount = case Variance of
                0 -> AvgHomes;
                V -> AvgHomes + rand:uniform(V * 2 + 1) - V - 1
            end,
            [make_home_entry(Region, N, H) || H <- lists:seq(1, max(1, HomeCount))]
        end,
        lists:seq(1, SrpCount)
    ),
    import_batched(Store, HomeEntries, BatchSize),

    {SrpCount, length(HomeEntries)}.

%% @private Create an SRP entry.
make_srp_entry(Region, SrpNum) ->
    SrpId = iolist_to_binary(io_lib:format("srp-~6..0B", [SrpNum])),
    MRI = <<"mri:srp:", ?REALM/binary, "/", Region/binary, "/", SrpId/binary>>,
    Metadata = #{
        type => srp,
        region => Region,
        capacity => 288,  %% Standard SRP port count
        active_ports => rand:uniform(288),
        status => active
    },
    {MRI, Metadata}.

%% @private Create a home connection entry.
make_home_entry(Region, SrpNum, HomeNum) ->
    SrpId = iolist_to_binary(io_lib:format("srp-~6..0B", [SrpNum])),
    HomeId = iolist_to_binary(io_lib:format("home-~8..0B", [HomeNum])),
    MRI = <<"mri:home:", ?REALM/binary, "/", Region/binary, "/", SrpId/binary, "/", HomeId/binary>>,
    Metadata = #{
        type => home,
        region => Region,
        srp => SrpId,
        connection_type => random_connection_type(),
        bandwidth => random_bandwidth(),
        status => active
    },
    {MRI, Metadata}.

%% @private Random connection type.
random_connection_type() ->
    case rand:uniform(10) of
        N when N =< 6 -> fiber;   %% 60% fiber
        N when N =< 9 -> vdsl;    %% 30% VDSL
        _ -> adsl                  %% 10% ADSL
    end.

%% @private Random bandwidth based on connection type.
random_bandwidth() ->
    case random_connection_type() of
        fiber -> lists:nth(rand:uniform(3), [100, 200, 1000]);  %% Mbps
        vdsl -> lists:nth(rand:uniform(3), [35, 50, 70]);
        adsl -> lists:nth(rand:uniform(2), [10, 20])
    end.

%% @private Import entries in batches.
import_batched(Store, Entries, BatchSize) ->
    Batches = split_into_batches(Entries, BatchSize),
    lists:foreach(
        fun(Batch) ->
            macula_mri_khepri_store:import(Store, Batch)
        end,
        Batches
    ).

%% @private Split list into batches.
split_into_batches(List, Size) ->
    split_into_batches(List, Size, []).

split_into_batches([], _Size, Acc) ->
    lists:reverse(Acc);
split_into_batches(List, Size, Acc) ->
    {Batch, Rest} = safe_split(Size, List),
    split_into_batches(Rest, Size, [Batch | Acc]).

safe_split(N, List) when length(List) =< N ->
    {List, []};
safe_split(N, List) ->
    lists:split(N, List).

%% @doc Clean up all demo data.
-spec cleanup_network(atom()) -> ok.
cleanup_network(Store) ->
    cleanup_network(Store, #{}).

-spec cleanup_network(atom(), map()) -> ok.
cleanup_network(Store, _Opts) ->
    io:format("Cleaning up TelcoX network...~n"),

    %% Delete all SRPs and homes under be.telcox realm
    %% Using Khepri delete with proper path pattern matching
    lists:foreach(
        fun(Type) ->
            %% Delete the entire type/realm subtree using wildcard pattern
            Path = [mri, Type, ?REALM, ?KHEPRI_WILDCARD_STAR_STAR],
            catch khepri:delete_many(Store, Path)
        end,
        [srp, home]
    ),

    io:format("Network cleaned up~n"),
    ok.

%%====================================================================
%% Query Demos
%%====================================================================

%% @doc Count MRIs by region.
-spec count_by_region(atom()) -> #{binary() => #{srps := non_neg_integer(), homes := non_neg_integer()}}.
count_by_region(Store) ->
    count_by_region(Store, #{}).

-spec count_by_region(atom(), map()) -> #{binary() => #{srps := non_neg_integer(), homes := non_neg_integer()}}.
count_by_region(Store, _Opts) ->
    Regions = [Region || {Region, _} <- ?REGIONS],
    maps:from_list([
        {Region, #{
            srps => count_type_in_region(Store, srp, Region),
            homes => count_type_in_region(Store, home, Region)
        }}
    || Region <- Regions]).

count_type_in_region(Store, Type, Region) ->
    %% Count by listing descendants and filtering
    BaseMRI = <<"mri:", (atom_to_binary(Type))/binary, ":", ?REALM/binary, "/", Region/binary>>,
    length(macula_mri_khepri_store:list_descendants(Store, BaseMRI)).

%% @doc List all SRPs in a region.
-spec list_srps_in_region(atom(), binary()) -> [binary()].
list_srps_in_region(Store, Region) ->
    list_srps_in_region(Store, Region, #{}).

-spec list_srps_in_region(atom(), binary(), map()) -> [binary()].
list_srps_in_region(Store, Region, _Opts) ->
    BaseMRI = <<"mri:srp:", ?REALM/binary, "/", Region/binary>>,
    macula_mri_khepri_store:list_children(Store, BaseMRI).

%% @doc List all homes connected to an SRP.
-spec list_homes_for_srp(atom(), binary()) -> [binary()].
list_homes_for_srp(Store, SrpMRI) ->
    list_homes_for_srp(Store, SrpMRI, #{}).

-spec list_homes_for_srp(atom(), binary(), map()) -> [binary()].
list_homes_for_srp(Store, SrpMRI, _Opts) ->
    %% Extract region and SRP ID from the SRP MRI
    %% mri:srp:be.telcox/region/srp-id -> mri:home:be.telcox/region/srp-id
    HomeMRI = binary:replace(SrpMRI, <<"mri:srp:">>, <<"mri:home:">>),
    macula_mri_khepri_store:list_children(Store, HomeMRI).

%%====================================================================
%% Benchmarking
%%====================================================================

%% @doc Run a comprehensive benchmark.
-spec benchmark(atom()) -> ok.
benchmark(Store) ->
    benchmark(Store, #{}).

%% @doc Run benchmark with options.
%% Options:
%%   - iterations: Number of iterations per operation (default: 100)
%%   - scale: Network scale factor (default: 0.01 = 1% of full scale)
-spec benchmark(atom(), map()) -> ok.
benchmark(Store, Opts) ->
    Iterations = maps:get(iterations, Opts, 100),
    Scale = maps:get(scale, Opts, 0.01),

    io:format("~n=== TelcoX Scale Benchmark ===~n"),
    io:format("Scale factor: ~p~n", [Scale]),
    io:format("Iterations: ~p~n~n", [Iterations]),

    %% Generate scaled network
    ScaledRegions = [{R, round(C * Scale)} || {R, C} <- ?REGIONS],
    ScaledHomesPerSrp = round(?AVG_HOMES_PER_SRP * Scale),

    io:format("--- Generating test data ---~n"),
    {GenTime, {ok, Stats}} = timer:tc(fun() ->
        generate_network(Store, #{
            regions => ScaledRegions,
            homes_per_srp => max(1, ScaledHomesPerSrp),
            batch_size => 500
        })
    end),
    io:format("Generation time: ~.2f ms~n", [GenTime / 1000]),
    io:format("SRPs: ~p, Homes: ~p~n~n", [maps:get(srps, Stats), maps:get(homes, Stats)]),

    %% Benchmark lookups
    io:format("--- Lookup Benchmark ---~n"),
    SampleSrps = sample_srps(Store, 10),
    {LookupTime, _} = timer:tc(fun() ->
        lists:foreach(fun(_) ->
            SrpMRI = lists:nth(rand:uniform(length(SampleSrps)), SampleSrps),
            macula_mri_khepri_store:lookup(Store, SrpMRI)
        end, lists:seq(1, Iterations))
    end),
    io:format("Random SRP lookup: ~.2f µs/op~n", [LookupTime / Iterations]),

    %% Benchmark list_children (homes per SRP)
    io:format("~n--- List Children Benchmark ---~n"),
    {ChildTime, _} = timer:tc(fun() ->
        lists:foreach(fun(_) ->
            SrpMRI = lists:nth(rand:uniform(length(SampleSrps)), SampleSrps),
            HomeMRI = binary:replace(SrpMRI, <<"mri:srp:">>, <<"mri:home:">>),
            macula_mri_khepri_store:list_children(Store, HomeMRI)
        end, lists:seq(1, min(Iterations, 20)))  %% Limit due to cost
    end),
    io:format("List homes for SRP: ~.2f µs/op~n", [ChildTime / min(Iterations, 20)]),

    %% Benchmark list_by_type
    io:format("~n--- List By Type Benchmark ---~n"),
    {TypeTime, Results} = timer:tc(fun() ->
        macula_mri_khepri_store:list_by_type(Store, srp, ?REALM)
    end),
    io:format("List all SRPs: ~.2f ms (~p results)~n", [TypeTime / 1000, length(Results)]),

    %% Benchmark count by region
    io:format("~n--- Count By Region Benchmark ---~n"),
    {CountTime, Counts} = timer:tc(fun() ->
        count_by_region(Store)
    end),
    io:format("Count by region: ~.2f ms~n", [CountTime / 1000]),
    maps:foreach(fun(Region, #{srps := S, homes := H}) ->
        io:format("  ~s: ~p SRPs, ~p homes~n", [Region, S, H])
    end, Counts),

    %% Cleanup
    io:format("~n--- Cleanup ---~n"),
    {CleanTime, _} = timer:tc(fun() ->
        cleanup_network(Store)
    end),
    io:format("Cleanup time: ~.2f ms~n", [CleanTime / 1000]),

    io:format("~n=== Benchmark Complete ===~n"),
    ok.

%% @private Sample some SRP MRIs for benchmarking.
sample_srps(Store, Count) ->
    AllSrps = macula_mri_khepri_store:list_by_type(Store, srp, ?REALM),
    case length(AllSrps) of
        0 -> [];
        N when N =< Count -> AllSrps;
        _ ->
            Indices = [rand:uniform(length(AllSrps)) || _ <- lists:seq(1, Count)],
            [lists:nth(I, AllSrps) || I <- lists:usort(Indices)]
    end.
