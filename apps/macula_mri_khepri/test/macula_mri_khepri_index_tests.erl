%%%-------------------------------------------------------------------
%%% @doc
%%% EUnit tests for macula_mri_khepri_index.
%%%
%%% Tests cover:
%%% - Index structure initialization
%%% - Index rebuilding
%%% - GenServer lifecycle
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_index_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

setup() ->
    meck:new(khepri, [passthrough]),
    %% Ensure any lingering GenServer is stopped
    case whereis(macula_mri_khepri_index) of
        undefined -> ok;
        Pid ->
            gen_server:stop(Pid, normal, 1000),
            timer:sleep(10)
    end,
    ok.

cleanup(_) ->
    %% Stop GenServer if running
    case whereis(macula_mri_khepri_index) of
        undefined -> ok;
        Pid ->
            gen_server:stop(Pid, normal, 1000),
            timer:sleep(10)
    end,
    meck:unload(khepri),
    ok.

%%====================================================================
%% Test Generators
%%====================================================================

index_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
        {"Start link creates GenServer", fun start_link_creates_genserver/0},
        {"Init sends initialize message", fun init_sends_initialize_message/0},
        {"Initialize indexes is no-op", fun initialize_indexes_is_no_op/0},
        {"Rebuild indexes clears old data", fun rebuild_indexes_clears_old_data/0},
        {"Rebuild indexes scans MRIs", fun rebuild_indexes_scans_mris/0},
        {"Parses standard MRI format", fun parses_standard_mri/0},
        {"Handles MRI without path", fun handles_mri_without_path/0},
        {"Handles deeply nested path", fun handles_deeply_nested_path/0}
     ]}.

%%====================================================================
%% GenServer Lifecycle Tests
%%====================================================================

start_link_creates_genserver() ->
    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    {ok, Pid} = macula_mri_khepri_index:start_link(test_store),

    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)).

init_sends_initialize_message() ->
    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    %% Start the GenServer
    {ok, Pid} = macula_mri_khepri_index:start_link(test_store),

    %% Give it time to process the initialize_indexes message
    timer:sleep(50),

    %% If it processed the message without crashing, it worked
    ?assert(is_process_alive(Pid)).

%%====================================================================
%% Index Structure Tests
%%====================================================================

initialize_indexes_is_no_op() ->
    %% Since v0.3.0, ensure_index_structure is a no-op because
    %% Khepri automatically creates paths when indexes are written.
    CreatedPaths = ets:new(created_paths, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> false end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        ets:insert(CreatedPaths, {path, Path}),
        ok
    end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),

    %% Wait for initialization
    timer:sleep(50),

    %% Verify NO paths were created during initialization
    %% (paths are created on-demand when indexes are written)
    AllPaths = [P || {path, P} <- ets:tab2list(CreatedPaths)],
    ?assertEqual([], AllPaths),

    ets:delete(CreatedPaths).

%%====================================================================
%% Rebuild Index Tests
%%====================================================================

rebuild_indexes_clears_old_data() ->
    %% Since v0.3.0, rebuild only clears existing indexes - it doesn't
    %% pre-create root paths (those are created on-demand during scan)
    DeletedPaths = ets:new(deleted_paths, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, delete, fun(_Store, Path) ->
        ets:insert(DeletedPaths, {path, Path}),
        ok
    end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),
    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),

    %% Wait for init
    timer:sleep(50),

    %% Clear captured paths before rebuild
    ets:delete_all_objects(DeletedPaths),

    %% Call rebuild
    ok = macula_mri_khepri_index:rebuild_indexes(test_store),

    %% Verify index was deleted
    AllDeleted = [P || {path, P} <- ets:tab2list(DeletedPaths)],
    ?assert(lists:member([mri_index], AllDeleted)),

    ets:delete(DeletedPaths).

rebuild_indexes_scans_mris() ->
    IndexedMRIs = ets:new(indexed_mris, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, delete, fun(_Store, _Path) -> ok end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        %% Capture type index writes
        case Path of
            [mri_index, by_type, _Type, _Realm, MRI] when is_binary(MRI) ->
                ets:insert(IndexedMRIs, {mri, MRI});
            _ ->
                ok
        end,
        ok
    end),

    %% Return some MRIs during scan
    MRIData = #{
        [mri, app, <<"io.macula">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/counter">>, name => <<"Counter">>},
        [mri, app, <<"io.macula">>, <<"timer">>] =>
            #{mri => <<"mri:app:io.macula/timer">>, name => <<"Timer">>}
    },

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri, '_'] -> {ok, MRIData};
            _ -> {ok, #{}}
        end
    end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),
    timer:sleep(50),

    %% Clear before rebuild
    ets:delete_all_objects(IndexedMRIs),

    %% Trigger rebuild
    ok = macula_mri_khepri_index:rebuild_indexes(test_store),

    %% Verify MRIs were indexed
    MRIs = [M || {mri, M} <- ets:tab2list(IndexedMRIs)],
    ?assert(lists:member(<<"mri:app:io.macula/counter">>, MRIs)),
    ?assert(lists:member(<<"mri:app:io.macula/timer">>, MRIs)),

    ets:delete(IndexedMRIs).

%%====================================================================
%% Parse MRI Tests (Internal Function)
%%====================================================================

%% Test via observable behavior since parse_mri is private

parses_standard_mri() ->
    IndexedMRIs = ets:new(indexed_mris, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, delete, fun(_Store, _Path) -> ok end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        case Path of
            [mri_index, by_type, Type, Realm, MRI] when is_binary(MRI) ->
                ets:insert(IndexedMRIs, {indexed, {Type, Realm, MRI}});
            _ ->
                ok
        end,
        ok
    end),

    MRIData = #{
        [mri, device, <<"io.proximus.be">>, <<"cabinet">>, <<"1234">>] =>
            #{mri => <<"mri:device:io.proximus.be/cabinet/1234">>, name => <<"Cabinet">>}
    },

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri, '_'] -> {ok, MRIData};
            _ -> {ok, #{}}
        end
    end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),
    timer:sleep(50),

    %% Clear before rebuild
    ets:delete_all_objects(IndexedMRIs),

    ok = macula_mri_khepri_index:rebuild_indexes(test_store),

    Indexed = [I || {indexed, I} <- ets:tab2list(IndexedMRIs)],
    ?assert(lists:member({device, <<"io.proximus.be">>, <<"mri:device:io.proximus.be/cabinet/1234">>}, Indexed)),

    ets:delete(IndexedMRIs).

handles_mri_without_path() ->
    IndexedMRIs = ets:new(indexed_mris, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, delete, fun(_Store, _Path) -> ok end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        case Path of
            [mri_index, by_type, Type, Realm, MRI] when is_binary(MRI) ->
                ets:insert(IndexedMRIs, {indexed, {Type, Realm, MRI}});
            _ ->
                ok
        end,
        ok
    end),

    MRIData = #{
        [mri, realm, <<"io.macula">>] =>
            #{mri => <<"mri:realm:io.macula">>, name => <<"Macula Realm">>}
    },

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri, '_'] -> {ok, MRIData};
            _ -> {ok, #{}}
        end
    end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),
    timer:sleep(50),

    %% Clear before rebuild
    ets:delete_all_objects(IndexedMRIs),

    ok = macula_mri_khepri_index:rebuild_indexes(test_store),

    Indexed = [I || {indexed, I} <- ets:tab2list(IndexedMRIs)],
    ?assert(lists:member({realm, <<"io.macula">>, <<"mri:realm:io.macula">>}, Indexed)),

    ets:delete(IndexedMRIs).

handles_deeply_nested_path() ->
    IndexedMRIs = ets:new(indexed_mris, [public, bag]),

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),
    meck:expect(khepri, delete, fun(_Store, _Path) -> ok end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        case Path of
            [mri_index, by_type, Type, Realm, MRI] when is_binary(MRI) ->
                ets:insert(IndexedMRIs, {indexed, {Type, Realm, MRI}});
            _ ->
                ok
        end,
        ok
    end),

    MRIData = #{
        [mri, asset, <<"io.macula">>, <<"org">>, <<"team">>, <<"proj">>, <<"file">>] =>
            #{mri => <<"mri:asset:io.macula/org/team/proj/file">>, name => <<"File">>}
    },

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri, '_'] -> {ok, MRIData};
            _ -> {ok, #{}}
        end
    end),

    {ok, _Pid} = macula_mri_khepri_index:start_link(test_store),
    timer:sleep(50),

    %% Clear before rebuild
    ets:delete_all_objects(IndexedMRIs),

    ok = macula_mri_khepri_index:rebuild_indexes(test_store),

    Indexed = [I || {indexed, I} <- ets:tab2list(IndexedMRIs)],
    ?assert(lists:member({asset, <<"io.macula">>, <<"mri:asset:io.macula/org/team/proj/file">>}, Indexed)),

    ets:delete(IndexedMRIs).
