%%%-------------------------------------------------------------------
%%% @doc
%%% Terminal User Interface for Proximus Network Demo.
%%%
%%% A self-contained TUI using ANSI escape codes to showcase
%%% the MRI storage capabilities at Proximus scale.
%%%
%%% Usage:
%%% ```
%%% macula_mri_khepri_tui:start().
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_tui).

-export([
    start/0,
    start/1
]).

-include_lib("khepri/include/khepri.hrl").

-define(DEFAULT_STORE, tui_demo_store).

%% ANSI escape codes
-define(ESC, "\e[").
-define(CLEAR, "\e[2J").
-define(HOME, "\e[H").
-define(HIDE_CURSOR, "\e[?25l").
-define(SHOW_CURSOR, "\e[?25h").
-define(BOLD, "\e[1m").
-define(DIM, "\e[2m").
-define(RESET, "\e[0m").
-define(GREEN, "\e[32m").
-define(YELLOW, "\e[33m").
-define(BLUE, "\e[34m").
-define(MAGENTA, "\e[35m").
-define(CYAN, "\e[36m").
-define(WHITE, "\e[37m").
-define(BG_BLUE, "\e[44m").
-define(BG_DEFAULT, "\e[49m").

%% Box drawing characters (Unicode)
-define(TL, "╭").  %% Top-left
-define(TR, "╮").  %% Top-right
-define(BL, "╰").  %% Bottom-left
-define(BR, "╯").  %% Bottom-right
-define(H, "─").   %% Horizontal
-define(V, "│").   %% Vertical
-define(LT, "├").  %% Left-T
-define(RT, "┤").  %% Right-T
-define(TT, "┬").  %% Top-T
-define(BT, "┴").  %% Bottom-T
-define(X, "┼").   %% Cross

%% State record
-record(state, {
    store :: atom(),
    data_dir :: string(),
    network_stats = #{} :: map(),
    metrics = #{} :: map(),
    status = idle :: idle | generating | ready,
    message = <<>> :: binary(),
    scale = 0.1 :: float()
}).

%%====================================================================
%% Public API
%%====================================================================

%% @doc Start the TUI demo.
-spec start() -> ok.
start() ->
    start(#{}).

%% @doc Start with options.
-spec start(map()) -> ok.
start(Opts) ->
    %% Set up terminal
    io:setopts([{encoding, unicode}]),
    ok = io:put_chars(?HIDE_CURSOR),

    try
        State = init_state(Opts),
        main_loop(State)
    catch
        Class:Reason:Stack ->
            %% Restore terminal before printing error
            io:put_chars(?SHOW_CURSOR),
            io:put_chars(?RESET),
            io:put_chars(?CLEAR),
            io:put_chars(?HOME),
            io:format("~nError: ~p:~p~n~p~n", [Class, Reason, Stack]),
            erlang:raise(Class, Reason, Stack)
    after
        %% Restore terminal
        io:put_chars(?SHOW_CURSOR),
        io:put_chars(?RESET),
        io:put_chars(?CLEAR),
        io:put_chars(?HOME)
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

init_state(Opts) ->
    Scale = maps:get(scale, Opts, 0.1),

    %% Start Khepri
    {ok, _} = application:ensure_all_started(ra),
    {ok, _} = application:ensure_all_started(khepri),

    DataDir = make_temp_dir(),

    RaConfig = #{
        name => ?DEFAULT_STORE,
        data_dir => DataDir,
        wal_data_dir => DataDir,
        names => ra_system:derive_names(?DEFAULT_STORE)
    },

    case ra_system:start(RaConfig) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,

    {ok, _} = khepri:start(?DEFAULT_STORE, ?DEFAULT_STORE),
    ok = khepri:fence(?DEFAULT_STORE, 10000),

    %% Initialize indexes
    lists:foreach(fun(Path) ->
        khepri:put(?DEFAULT_STORE, Path, #{initialized => true})
    end, [
        [mri_index, by_type],
        [mri_index, by_realm],
        [mri_rel, forward],
        [mri_rel, reverse]
    ]),

    #state{
        store = ?DEFAULT_STORE,
        data_dir = DataDir,
        scale = Scale,
        message = <<"Welcome! Press [G] to generate network.">>
    }.

main_loop(State) ->
    render(State),

    case get_key() of
        $g -> main_loop(handle_generate(State));
        $G -> main_loop(handle_generate(State));
        $q -> main_loop(handle_query(State));
        $Q -> main_loop(handle_query(State));
        $b -> main_loop(handle_benchmark(State));
        $B -> main_loop(handle_benchmark(State));
        $c -> main_loop(handle_clear(State));
        $C -> main_loop(handle_clear(State));
        $+ -> main_loop(handle_scale_up(State));
        $- -> main_loop(handle_scale_down(State));
        27 -> handle_exit(State);  %% ESC
        $x -> handle_exit(State);
        $X -> handle_exit(State);
        _ -> main_loop(State)
    end.

%%====================================================================
%% Rendering
%%====================================================================

render(#state{} = State) ->
    %% Use 'user' device for proper shell I/O
    io:format(user, "~s~s", [?CLEAR, ?HOME]),

    render_header(),
    render_status_bar(State),
    render_network_table(State),
    render_metrics(State),
    render_help(),
    render_message(State),

    ok.

render_header() ->
    io:put_chars(?BOLD ++ ?CYAN),
    io:put_chars("\n"),
    io:put_chars("  " ++ ?TL ++ string:copies(?H, 60) ++ ?TR ++ "\n"),
    io:put_chars("  " ++ ?V ++ ?BG_BLUE ++ "  MACULA MRI" ++ ?BG_DEFAULT ++
                 " - Proximus Network Scale Demo                  " ++ ?V ++ "\n"),
    io:put_chars("  " ++ ?BL ++ string:copies(?H, 60) ++ ?BR ++ "\n"),
    io:put_chars(?RESET),
    io:put_chars("\n").

render_status_bar(#state{status = Status, network_stats = Stats, scale = Scale}) ->
    {Progress, Total} = case Status of
        idle -> {0, 1};
        generating -> {maps:get(current, Stats, 0), maps:get(total, Stats, 1)};
        ready -> {1, 1}
    end,

    ScalePercent = round(Scale * 100),
    StatusText = case Status of
        idle -> ?DIM ++ "Not Generated" ++ ?RESET;
        generating -> ?YELLOW ++ "Generating..." ++ ?RESET;
        ready -> ?GREEN ++ "Ready" ++ ?RESET
    end,

    %% Scale indicator
    io:put_chars("  Scale: " ++ ?BOLD ++ integer_to_list(ScalePercent) ++ "%" ++ ?RESET ++
                 ?DIM ++ " (press +/- to adjust)" ++ ?RESET ++ "\n"),

    %% Progress bar - ultra simple
    BarWidth = 40,
    Pct = case {is_number(Progress), is_number(Total), Total} of
        {true, true, T} when T > 0 -> (Progress / T);
        _ -> 0.0
    end,
    %% Clamp percentage to 0.0-1.0
    ClampedPct = if Pct < 0.0 -> 0.0; Pct > 1.0 -> 1.0; true -> Pct end,
    FilledFloat = ClampedPct * BarWidth,
    FilledInt = trunc(FilledFloat),
    %% Final safety: ensure 0 <= Filled <= 40
    SafeFilled = if FilledInt < 0 -> 0; FilledInt > 40 -> 40; true -> FilledInt end,
    SafeEmpty = 40 - SafeFilled,

    Bar = ?GREEN ++ string:copies("█", SafeFilled) ++
          ?DIM ++ string:copies("░", SafeEmpty) ++ ?RESET,

    Percent = case Total of
        0 -> 0;
        T2 -> round((Progress / T2) * 100)
    end,

    io:put_chars("  Status: " ++ StatusText ++ "  "),
    io:put_chars("[" ++ Bar ++ "] " ++ integer_to_list(Percent) ++ "%\n\n").

render_network_table(#state{network_stats = Stats}) ->
    Regions = [
        {<<"brussels">>, "Brussels", 400},
        {<<"flanders">>, "Flanders", 2200},
        {<<"wallonia">>, "Wallonia", 1400}
    ],

    io:put_chars(?BOLD ++ "  Network Topology\n" ++ ?RESET),
    io:put_chars("  ┌" ++ string:copies("─", 14) ++ "┬" ++
                 string:copies("─", 10) ++ "┬" ++
                 string:copies("─", 12) ++ "┬" ++
                 string:copies("─", 12) ++ "┐\n"),
    io:put_chars("  │" ++ ?BOLD ++ " Region       " ++ ?RESET ++ "│" ++
                 ?BOLD ++ " SRPs     " ++ ?RESET ++ "│" ++
                 ?BOLD ++ " Homes      " ++ ?RESET ++ "│" ++
                 ?BOLD ++ " Status     " ++ ?RESET ++ "│\n"),
    io:put_chars("  ├" ++ string:copies("─", 14) ++ "┼" ++
                 string:copies("─", 10) ++ "┼" ++
                 string:copies("─", 12) ++ "┼" ++
                 string:copies("─", 12) ++ "┤\n"),

    lists:foreach(fun({Key, Name, _MaxSrps}) ->
        RegionStats = maps:get(Key, Stats, #{}),
        Srps = maps:get(srps, RegionStats, 0),
        Homes = maps:get(homes, RegionStats, 0),
        Status = maps:get(status, RegionStats, pending),

        StatusStr = case Status of
            complete -> ?GREEN ++ "✓ Complete " ++ ?RESET;
            building -> ?YELLOW ++ "◐ Building " ++ ?RESET;
            pending -> ?DIM ++ "○ Pending  " ++ ?RESET
        end,

        %% Build row manually to handle ANSI codes properly
        io:put_chars([
            "  │ ", pad_right(Name, 12), " │ ",
            pad_left(format_number(Srps), 8), " │ ",
            pad_left(format_number(Homes), 10), " │ ",
            StatusStr, "│\n"
        ])
    end, Regions),

    io:put_chars("  └" ++ string:copies("─", 14) ++ "┴" ++
                 string:copies("─", 10) ++ "┴" ++
                 string:copies("─", 12) ++ "┴" ++
                 string:copies("─", 12) ++ "┘\n"),

    %% Totals
    TotalSrps = lists:sum([maps:get(srps, maps:get(R, Stats, #{}), 0)
                           || {R, _, _} <- Regions]),
    TotalHomes = lists:sum([maps:get(homes, maps:get(R, Stats, #{}), 0)
                            || {R, _, _} <- Regions]),

    io:put_chars(?BOLD),
    io:put_chars(io_lib:format("  Total: ~s SRPs, ~s Homes~n", [
        format_number(TotalSrps),
        format_number(TotalHomes)
    ])),
    io:put_chars(?RESET ++ "\n").

render_metrics(#state{metrics = Metrics}) ->
    io:put_chars(?BOLD ++ "  Performance Metrics\n" ++ ?RESET),

    case maps:size(Metrics) of
        0 ->
            io:put_chars(?DIM ++ "  └── Run [B]enchmark to measure performance\n" ++ ?RESET);
        _ ->
            Lookup = maps:get(lookup_us, Metrics, 0),
            Children = maps:get(children_ms, Metrics, 0),
            TypeQuery = maps:get(type_query_ms, Metrics, 0),
            RegionQuery = maps:get(region_query_ms, Metrics, 0),

            io:put_chars(io_lib:format("  ├── SRP Lookup:      ~s~n", [format_metric(Lookup, "µs")])),
            io:put_chars(io_lib:format("  ├── List Children:   ~s~n", [format_metric(Children, "ms")])),
            io:put_chars(io_lib:format("  ├── Type Query:      ~s~n", [format_metric(TypeQuery, "ms")])),
            io:put_chars(io_lib:format("  └── Region Count:    ~s~n", [format_metric(RegionQuery, "ms")]))
    end,
    io:put_chars("\n").

render_help() ->
    io:put_chars(?DIM),
    io:put_chars("  ─────────────────────────────────────────────────────────────\n"),
    io:put_chars("  [G]enerate Network   [Q]uery Demo   [B]enchmark   [C]lear\n"),
    io:put_chars("  [+/-] Adjust Scale   [X/ESC] Exit\n"),
    io:put_chars("  ─────────────────────────────────────────────────────────────\n"),
    io:put_chars(?RESET).

render_message(#state{message = Msg}) ->
    io:put_chars("\n  " ++ ?CYAN ++ binary_to_list(Msg) ++ ?RESET ++ "\n").

%%====================================================================
%% Event Handlers
%%====================================================================

handle_generate(#state{store = Store, scale = Scale} = State) ->
    %% Debug: show we're starting
    io:format(user, "~n>>> Starting generation...~n", []),

    %% Clear existing data first
    State1 = handle_clear(State#state{message = <<"Clearing previous data...">>}),
    render(State1),
    timer:sleep(200),  %% Brief pause so user sees the clear

    Regions = [
        {<<"brussels">>, round(400 * Scale)},
        {<<"flanders">>, round(2200 * Scale)},
        {<<"wallonia">>, round(1400 * Scale)}
    ],

    TotalSrps = lists:sum([C || {_, C} <- Regions]),
    HomesPerSrp = round(250 * Scale),

    %% We estimate total work units: each SRP is 1 unit, each home batch is 1 unit
    %% Roughly: TotalSrps + (TotalSrps * HomesPerSrp / 500) batches
    EstimatedHomeUnits = TotalSrps * 2,  %% rough estimate for home work
    TotalUnits = TotalSrps + EstimatedHomeUnits,

    State2 = State1#state{
        status = generating,
        network_stats = #{total => TotalUnits, current => 0}
    },

    render(State2#state{message = <<"Starting generation...">>}),

    %% Generate each region with progress updates
    {FinalStats, _FinalProgress} = lists:foldl(fun({Region, SrpCount}, {AccStats, Progress}) ->
        %% Update status to building for this region
        NewStats = AccStats#{
            Region => #{srps => 0, homes => 0, status => building}
        },

        %% Show we're starting SRPs for this region
        render(State2#state{
            network_stats = NewStats#{total => TotalUnits, current => Progress},
            message = iolist_to_binary([<<"Generating ">>, Region, <<" SRPs (0/">>, integer_to_binary(max(1, SrpCount)), <<")...">>])
        }),

        %% Generate SRPs with per-batch progress
        SrpEntries = [make_srp_entry(Region, N) || N <- lists:seq(1, max(1, SrpCount))],
        SrpBatchSize = 50,
        SrpBatches = split_batches(SrpEntries, SrpBatchSize),

        {_, SrpProgress} = lists:foldl(fun(Batch, {BatchIdx, _ProgressAcc}) ->
            macula_mri_khepri_store:import(Store, Batch),
            EntriesDone = min(BatchIdx * SrpBatchSize, length(SrpEntries)),
            NewProgress = Progress + BatchIdx,
            %% Debug: simple progress line
            io:format(user, "\r>>> ~s: SRPs ~B/~B   ", [Region, EntriesDone, max(1, SrpCount)]),
            render(State2#state{
                network_stats = NewStats#{total => TotalUnits, current => NewProgress},
                message = iolist_to_binary([
                    Region, <<": SRPs ">>,
                    integer_to_binary(EntriesDone), <<"/">>,
                    integer_to_binary(max(1, SrpCount))
                ])
            }),
            timer:sleep(50),  %% Let terminal refresh
            {BatchIdx + 1, NewProgress}
        end, {1, Progress}, SrpBatches),

        %% Update stats after SRPs done
        SrpsDoneStats = NewStats#{Region => #{srps => max(1, SrpCount), homes => 0, status => building}},

        %% Now generate homes
        render(State2#state{
            network_stats = SrpsDoneStats#{total => TotalUnits, current => SrpProgress},
            message = iolist_to_binary([Region, <<": Generating homes...">>])
        }),

        %% Build home entries for all SRPs in this region
        HomeEntries = lists:flatmap(fun(N) ->
            HomeCount = max(1, HomesPerSrp + rand:uniform(max(1, round(50 * Scale))) - round(25 * Scale)),
            [make_home_entry(Region, N, H) || H <- lists:seq(1, HomeCount)]
        end, lists:seq(1, max(1, SrpCount))),

        TotalHomeEntries = length(HomeEntries),
        HomeBatchSize = 200,
        HomeBatches = split_batches(HomeEntries, HomeBatchSize),

        %% Import homes with progress
        {_, HomeProgress} = lists:foldl(fun(Batch, {BatchIdx, _ProgressAcc}) ->
            macula_mri_khepri_store:import(Store, Batch),
            EntriesDone = min(BatchIdx * HomeBatchSize, TotalHomeEntries),
            NewProgress = SrpProgress + BatchIdx,
            render(State2#state{
                network_stats = SrpsDoneStats#{total => TotalUnits, current => NewProgress},
                message = iolist_to_binary([
                    Region, <<": Homes ">>,
                    format_number_bin(EntriesDone), <<"/">>,
                    format_number_bin(TotalHomeEntries)
                ])
            }),
            timer:sleep(30),  %% Let terminal refresh
            {BatchIdx + 1, NewProgress}
        end, {1, SrpProgress}, HomeBatches),

        %% Mark region complete
        RegionStats = #{
            srps => max(1, SrpCount),
            homes => TotalHomeEntries,
            status => complete
        },

        {AccStats#{Region => RegionStats}, HomeProgress}
    end, {#{}, 0}, Regions),

    TotalHomes = lists:sum([maps:get(homes, maps:get(R, FinalStats, #{}), 0)
                            || {R, _} <- Regions]),

    State2#state{
        status = ready,
        network_stats = FinalStats#{total => TotalUnits, current => TotalUnits},
        message = iolist_to_binary(io_lib:format(
            "Network generated: ~s SRPs, ~s homes",
            [format_number(TotalSrps), format_number(TotalHomes)]))
    }.

handle_query(#state{status = idle} = State) ->
    State#state{message = <<"Generate a network first with [G]">>};
handle_query(#state{store = Store} = State) ->
    %% Sample query: find all SRPs in Brussels
    {Time1, Brussels} = timer:tc(fun() ->
        macula_mri_khepri_store:list_by_type(Store, srp, <<"be.proximus">>)
    end),

    BrusselsSrps = [S || S <- Brussels,
                         binary:match(S, <<"brussels">>) =/= nomatch],

    Msg = iolist_to_binary(io_lib:format(
        "Query: Found ~p SRPs in Brussels (~.2f ms)",
        [length(BrusselsSrps), Time1 / 1000])),

    State#state{message = Msg}.

handle_benchmark(#state{status = idle} = State) ->
    State#state{message = <<"Generate a network first with [G]">>};
handle_benchmark(#state{store = Store} = State) ->
    State1 = State#state{message = <<"Running benchmark...">>},
    render(State1),

    %% Get sample SRPs
    AllSrps = macula_mri_khepri_store:list_by_type(Store, srp, <<"be.proximus">>),
    SampleSrps = case length(AllSrps) of
        0 -> [];
        N -> [lists:nth(rand:uniform(N), AllSrps) || _ <- lists:seq(1, min(10, N))]
    end,

    Metrics = case SampleSrps of
        [] ->
            #{};
        _ ->
            %% Lookup benchmark
            {LookupTime, _} = timer:tc(fun() ->
                lists:foreach(fun(_) ->
                    SrpMRI = lists:nth(rand:uniform(length(SampleSrps)), SampleSrps),
                    macula_mri_khepri_store:lookup(Store, SrpMRI)
                end, lists:seq(1, 50))
            end),

            %% Children benchmark
            {ChildTime, _} = timer:tc(fun() ->
                lists:foreach(fun(_) ->
                    SrpMRI = lists:nth(rand:uniform(length(SampleSrps)), SampleSrps),
                    HomeMRI = binary:replace(SrpMRI, <<"mri:srp:">>, <<"mri:home:">>),
                    macula_mri_khepri_store:list_children(Store, HomeMRI)
                end, lists:seq(1, 10))
            end),

            %% Type query benchmark
            {TypeTime, _} = timer:tc(fun() ->
                macula_mri_khepri_store:list_by_type(Store, srp, <<"be.proximus">>)
            end),

            %% Region count benchmark
            {RegionTime, _} = timer:tc(fun() ->
                macula_mri_khepri_proximus_demo:count_by_region(Store)
            end),

            #{
                lookup_us => LookupTime / 50,
                children_ms => ChildTime / 10 / 1000,
                type_query_ms => TypeTime / 1000,
                region_query_ms => RegionTime / 1000
            }
    end,

    State#state{
        metrics = Metrics,
        message = <<"Benchmark complete!">>
    }.

handle_clear(#state{store = Store} = State) ->
    %% Clear all demo data
    catch khepri:delete_many(Store, [mri, srp, <<"be.proximus">>, ?KHEPRI_WILDCARD_STAR_STAR]),
    catch khepri:delete_many(Store, [mri, home, <<"be.proximus">>, ?KHEPRI_WILDCARD_STAR_STAR]),
    catch khepri:delete_many(Store, [mri_index, by_type, srp, <<"be.proximus">>, ?KHEPRI_WILDCARD_STAR_STAR]),
    catch khepri:delete_many(Store, [mri_index, by_type, home, <<"be.proximus">>, ?KHEPRI_WILDCARD_STAR_STAR]),
    catch khepri:delete_many(Store, [mri_index, by_realm, <<"be.proximus">>, ?KHEPRI_WILDCARD_STAR_STAR]),

    State#state{
        status = idle,
        network_stats = #{},
        metrics = #{},
        message = <<"Network cleared.">>
    }.

handle_scale_up(#state{scale = Scale} = State) ->
    NewScale = min(1.0, Scale + 0.05),
    State#state{
        scale = NewScale,
        message = iolist_to_binary(io_lib:format(
            "Scale set to ~p% (~p SRPs, ~p homes at full generation)",
            [round(NewScale * 100), round(4000 * NewScale), round(1000000 * NewScale)]))
    }.

handle_scale_down(#state{scale = Scale} = State) ->
    NewScale = max(0.01, Scale - 0.05),
    State#state{
        scale = NewScale,
        message = iolist_to_binary(io_lib:format(
            "Scale set to ~p% (~p SRPs, ~p homes at full generation)",
            [round(NewScale * 100), round(4000 * NewScale), round(1000000 * NewScale)]))
    }.

handle_exit(#state{store = Store, data_dir = DataDir}) ->
    %% Cleanup
    catch khepri:stop(Store),
    catch ra_system:stop(Store),
    timer:sleep(100),
    os:cmd("rm -rf " ++ DataDir),
    ok.

%%====================================================================
%% Helpers
%%====================================================================

get_key() ->
    %% Read a line and take the first character
    %% This works better with rebar3 shell than get_chars
    case io:get_line("") of
        eof -> 27;
        {error, _} -> 27;
        "\n" -> 0;  %% Just enter pressed
        [C | _] -> C
    end.

make_temp_dir() ->
    TempBase = "/tmp/macula_mri_tui",
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Dir = TempBase ++ "_" ++ Unique,
    ok = filelib:ensure_dir(Dir ++ "/"),
    Dir.

format_number(N) when N >= 1000000 ->
    lists:flatten(io_lib:format("~.1fM", [N / 1000000]));
format_number(N) when N >= 1000 ->
    lists:flatten(io_lib:format("~.1fK", [N / 1000]));
format_number(N) ->
    integer_to_list(N).

%% Same as format_number but returns binary for iolist building
format_number_bin(N) when N >= 1000000 ->
    iolist_to_binary(io_lib:format("~.1fM", [N / 1000000]));
format_number_bin(N) when N >= 1000 ->
    iolist_to_binary(io_lib:format("~.1fK", [N / 1000]));
format_number_bin(N) ->
    integer_to_binary(N).

pad_left(Str, Width) ->
    S = lists:flatten(Str),
    Len = length(S),
    if Len >= Width -> S;
       true -> lists:duplicate(Width - Len, $\s) ++ S
    end.

pad_right(Str, Width) ->
    S = lists:flatten(Str),
    Len = length(S),
    if Len >= Width -> S;
       true -> S ++ lists:duplicate(Width - Len, $\s)
    end.

format_metric(Value, Unit) when is_float(Value) ->
    Color = if
        Value < 100 -> ?GREEN;
        Value < 1000 -> ?YELLOW;
        true -> ?MAGENTA
    end,
    Color ++ io_lib:format("~.1f ~s", [Value, Unit]) ++ ?RESET;
format_metric(Value, Unit) ->
    format_metric(float(Value), Unit).

make_srp_entry(Region, SrpNum) ->
    SrpId = iolist_to_binary(io_lib:format("srp-~6..0B", [SrpNum])),
    MRI = <<"mri:srp:be.proximus/", Region/binary, "/", SrpId/binary>>,
    Metadata = #{
        type => srp,
        region => Region,
        capacity => 288,
        active_ports => rand:uniform(288),
        status => active
    },
    {MRI, Metadata}.

make_home_entry(Region, SrpNum, HomeNum) ->
    SrpId = iolist_to_binary(io_lib:format("srp-~6..0B", [SrpNum])),
    HomeId = iolist_to_binary(io_lib:format("home-~8..0B", [HomeNum])),
    MRI = <<"mri:home:be.proximus/", Region/binary, "/", SrpId/binary, "/", HomeId/binary>>,
    Metadata = #{
        type => home,
        region => Region,
        srp => SrpId,
        connection_type => fiber,
        bandwidth => 100,
        status => active
    },
    {MRI, Metadata}.

split_batches(List, Size) ->
    split_batches(List, Size, []).

split_batches([], _Size, Acc) ->
    lists:reverse(Acc);
split_batches(List, Size, Acc) when length(List) =< Size ->
    lists:reverse([List | Acc]);
split_batches(List, Size, Acc) ->
    {Batch, Rest} = lists:split(Size, List),
    split_batches(Rest, Size, [Batch | Acc]).
