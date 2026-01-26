%%%-------------------------------------------------------------------
%%% @doc
%%% Tests for the Proximus scale demo module.
%%%
%%% Uses a real Khepri store to test the demo functionality at a
%%% small scale to verify correctness.
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_proximus_demo_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_STORE, proximus_demo_test_store).

%%====================================================================
%% Test Fixtures
%%====================================================================

make_temp_dir() ->
    TempBase = "/tmp/macula_mri_proximus_test",
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Dir = TempBase ++ "_" ++ Unique,
    ok = filelib:ensure_dir(Dir ++ "/"),
    Dir.

delete_dir(Dir) ->
    case filelib:is_dir(Dir) of
        true ->
            {ok, Files} = file:list_dir(Dir),
            lists:foreach(fun(F) ->
                Path = filename:join(Dir, F),
                case filelib:is_dir(Path) of
                    true -> delete_dir(Path);
                    false -> file:delete(Path)
                end
            end, Files),
            file:del_dir(Dir);
        false ->
            ok
    end.

setup() ->
    %% Unload any meck mocks
    lists:foreach(fun(Mod) ->
        catch meck:unload(Mod)
    end, [khepri, khepri_tx]),

    %% Start required applications
    {ok, _} = application:ensure_all_started(ra),
    {ok, _} = application:ensure_all_started(khepri),

    DataDir = make_temp_dir(),

    RaSystemConfig = #{
        name => ?TEST_STORE,
        data_dir => DataDir,
        wal_data_dir => DataDir,
        names => ra_system:derive_names(?TEST_STORE)
    },

    case ra_system:start(RaSystemConfig) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,

    {ok, _} = khepri:start(?TEST_STORE, ?TEST_STORE),
    ok = khepri:fence(?TEST_STORE, 10000),

    %% Initialize index structure
    lists:foreach(fun(Path) ->
        khepri:put(?TEST_STORE, Path, #{initialized => true})
    end, [
        [mri_index, by_type],
        [mri_index, by_realm],
        [mri_rel, forward],
        [mri_rel, reverse]
    ]),
    DataDir.

cleanup(DataDir) ->
    catch khepri:stop(?TEST_STORE),
    catch ra_system:stop(?TEST_STORE),
    timer:sleep(200),
    delete_dir(DataDir),
    ok.

%%====================================================================
%% Test Suite
%%====================================================================

proximus_demo_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun test_generate_small_network/1,
         fun test_count_by_region/1,
         fun test_list_srps_in_region/1,
         fun test_list_homes_for_srp/1,
         fun test_cleanup_network/1
     ]}.

%%====================================================================
%% Individual Tests
%%====================================================================

test_generate_small_network(_DataDir) ->
    {"Generate a small test network", fun() ->
        %% Generate a very small network for testing
        SmallRegions = [
            {<<"brussels">>, 2},
            {<<"flanders">>, 3},
            {<<"wallonia">>, 2}
        ],
        {ok, Stats} = macula_mri_khepri_proximus_demo:generate_network(?TEST_STORE, #{
            regions => SmallRegions,
            homes_per_srp => 5,
            homes_variance => 2,
            batch_size => 10
        }),

        %% Verify counts
        ?assertEqual(7, maps:get(srps, Stats)),
        ?assert(maps:get(homes, Stats) > 0),
        ?assert(maps:get(homes, Stats) =< 7 * 7)  %% Max 7 homes per SRP with variance
    end}.

test_count_by_region(_DataDir) ->
    {"Count MRIs by region", fun() ->
        %% Generate a small network
        SmallRegions = [
            {<<"brussels">>, 2},
            {<<"flanders">>, 3}
        ],
        {ok, _} = macula_mri_khepri_proximus_demo:generate_network(?TEST_STORE, #{
            regions => SmallRegions,
            homes_per_srp => 3,
            homes_variance => 0,
            batch_size => 10
        }),

        %% Count by region
        Counts = macula_mri_khepri_proximus_demo:count_by_region(?TEST_STORE),

        %% Verify Brussels
        BrusselsStats = maps:get(<<"brussels">>, Counts, #{srps => 0, homes => 0}),
        ?assertEqual(2, maps:get(srps, BrusselsStats)),
        ?assertEqual(6, maps:get(homes, BrusselsStats)),

        %% Verify Flanders
        FlandersStats = maps:get(<<"flanders">>, Counts, #{srps => 0, homes => 0}),
        ?assertEqual(3, maps:get(srps, FlandersStats)),
        ?assertEqual(9, maps:get(homes, FlandersStats))
    end}.

test_list_srps_in_region(_DataDir) ->
    {"List SRPs in a region", fun() ->
        SmallRegions = [
            {<<"brussels">>, 3}
        ],
        {ok, _} = macula_mri_khepri_proximus_demo:generate_network(?TEST_STORE, #{
            regions => SmallRegions,
            homes_per_srp => 2,
            homes_variance => 0,
            batch_size => 10
        }),

        %% List SRPs in Brussels
        Srps = macula_mri_khepri_proximus_demo:list_srps_in_region(?TEST_STORE, <<"brussels">>),
        ?assertEqual(3, length(Srps)),

        %% Verify MRI format
        [FirstSrp | _] = Srps,
        ?assert(binary:match(FirstSrp, <<"mri:srp:be.proximus/brussels/">>) =/= nomatch)
    end}.

test_list_homes_for_srp(_DataDir) ->
    {"List homes for a specific SRP", fun() ->
        SmallRegions = [
            {<<"brussels">>, 1}
        ],
        {ok, _} = macula_mri_khepri_proximus_demo:generate_network(?TEST_STORE, #{
            regions => SmallRegions,
            homes_per_srp => 5,
            homes_variance => 0,
            batch_size => 10
        }),

        %% Get the SRP
        [SrpMRI] = macula_mri_khepri_proximus_demo:list_srps_in_region(?TEST_STORE, <<"brussels">>),

        %% List homes for this SRP
        Homes = macula_mri_khepri_proximus_demo:list_homes_for_srp(?TEST_STORE, SrpMRI),
        ?assertEqual(5, length(Homes)),

        %% Verify home MRI format
        [FirstHome | _] = Homes,
        ?assert(binary:match(FirstHome, <<"mri:home:be.proximus/brussels/">>) =/= nomatch)
    end}.

test_cleanup_network(_DataDir) ->
    {"Cleanup removes all demo data", fun() ->
        SmallRegions = [
            {<<"brussels">>, 2},
            {<<"flanders">>, 2}
        ],
        {ok, _} = macula_mri_khepri_proximus_demo:generate_network(?TEST_STORE, #{
            regions => SmallRegions,
            homes_per_srp => 3,
            homes_variance => 0,
            batch_size => 10
        }),

        %% Verify data exists
        Srps = macula_mri_khepri_store:list_by_type(?TEST_STORE, srp, <<"be.proximus">>),
        ?assertEqual(4, length(Srps)),

        %% Cleanup
        ok = macula_mri_khepri_proximus_demo:cleanup_network(?TEST_STORE),

        %% Verify data is gone
        SrpsAfter = macula_mri_khepri_store:list_by_type(?TEST_STORE, srp, <<"be.proximus">>),
        ?assertEqual(0, length(SrpsAfter))
    end}.
