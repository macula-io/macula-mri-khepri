%%%-------------------------------------------------------------------
%%% @doc
%%% Integration tests for macula_mri_khepri using a real Khepri store.
%%%
%%% Unlike the unit tests that use meck mocks, these tests start an
%%% actual Khepri instance with Raft consensus to verify real behavior.
%%%
%%% Each test uses a unique temporary directory that is cleaned up
%%% after the test completes.
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_integration_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("khepri/include/khepri.hrl").

-define(TEST_STORE, integration_test_store).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Generate a unique temp directory for each test run.
make_temp_dir() ->
    TempBase = "/tmp/macula_mri_khepri_test",
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Dir = TempBase ++ "_" ++ Unique,
    ok = filelib:ensure_dir(Dir ++ "/"),
    Dir.

%% @doc Recursively delete a directory.
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

%% @doc Setup: start a real Khepri store.
setup() ->
    %% IMPORTANT: Unload any meck mocks from unit tests to ensure clean state
    %% This prevents unit test mocks from interfering with integration tests
    lists:foreach(fun(Mod) ->
        catch meck:unload(Mod)
    end, [khepri, khepri_tx]),

    %% Start required applications (Ra and Khepri)
    {ok, _} = application:ensure_all_started(ra),
    {ok, _} = application:ensure_all_started(khepri),

    DataDir = make_temp_dir(),

    %% Start Khepri with a custom Ra system for this test
    %% When given a data_dir, Khepri creates its own Ra system
    RaSystemConfig = #{
        name => ?TEST_STORE,
        data_dir => DataDir,
        wal_data_dir => DataDir,
        names => ra_system:derive_names(?TEST_STORE)
    },

    %% Start the Ra system
    case ra_system:start(RaSystemConfig) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,

    %% Start Khepri store on our Ra system
    %% khepri:start(RaSystem, StoreIdOrConfig) returns {ok, StoreId}
    {ok, _StoreId} = khepri:start(?TEST_STORE, ?TEST_STORE),

    %% Wait for Khepri to be ready using fence
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

%% @doc Cleanup: stop Khepri and delete temp directory.
cleanup(DataDir) ->
    %% Stop the Khepri store
    catch khepri:stop(?TEST_STORE),
    %% Stop the Ra system
    catch ra_system:stop(?TEST_STORE),
    %% Small delay to ensure files are released
    timer:sleep(200),
    %% Delete temp directory
    delete_dir(DataDir),
    ok.

%%====================================================================
%% Test Generator
%%====================================================================

integration_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
      %% Store CRUD tests
      fun test_register_and_lookup/1,
      fun test_register_already_exists/1,
      fun test_lookup_not_found/1,
      fun test_update_existing/1,
      fun test_delete_existing/1,
      fun test_exists_check/1,

      %% Tree query tests
      fun test_list_children/1,
      fun test_list_descendants/1,
      fun test_list_by_type/1,
      fun test_count_children/1,

      %% Bulk operation tests
      fun test_import_multiple/1,
      fun test_export_subtree/1,

      %% Graph relationship tests
      fun test_create_relationship/1,
      fun test_delete_relationship/1,
      fun test_related_to_query/1,
      fun test_related_from_query/1,
      fun test_all_related/1,
      fun test_traverse_single_hop/1,
      fun test_traverse_transitive/1,
      fun test_traverse_with_cycles/1,

      %% Taxonomy tests
      fun test_instances_of/1,
      fun test_instances_of_transitive/1,
      fun test_class_hierarchy/1
     ]}.

%%====================================================================
%% Store CRUD Tests
%%====================================================================

test_register_and_lookup(_DataDir) ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    Metadata = #{name => <<"Counter">>, version => <<"1.0.0">>},

    ?_test(begin
        %% Register
        ok = macula_mri_khepri_store:register(?TEST_STORE, MRI, Metadata),

        %% Lookup
        {ok, Result} = macula_mri_khepri_store:lookup(?TEST_STORE, MRI),

        %% Verify
        ?assertEqual(<<"Counter">>, maps:get(name, Result)),
        ?assertEqual(<<"1.0.0">>, maps:get(version, Result)),
        ?assertEqual(MRI, maps:get(mri, Result)),
        ?assert(is_integer(maps:get(registered_at, Result)))
    end).

test_register_already_exists(_DataDir) ->
    MRI = <<"mri:app:io.macula/acme/counter2">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, MRI, #{}),
        Result = macula_mri_khepri_store:register(?TEST_STORE, MRI, #{}),
        ?assertEqual({error, already_exists}, Result)
    end).

test_lookup_not_found(_DataDir) ->
    ?_test(begin
        Result = macula_mri_khepri_store:lookup(?TEST_STORE, <<"mri:app:io.macula/nonexistent">>),
        ?assertEqual({error, not_found}, Result)
    end).

test_update_existing(_DataDir) ->
    MRI = <<"mri:app:io.macula/acme/updatable">>,

    ?_test(begin
        %% Register
        ok = macula_mri_khepri_store:register(?TEST_STORE, MRI, #{name => <<"Original">>}),

        %% Update
        ok = macula_mri_khepri_store:update(?TEST_STORE, MRI, #{name => <<"Updated">>, extra => <<"field">>}),

        %% Verify
        {ok, Result} = macula_mri_khepri_store:lookup(?TEST_STORE, MRI),
        ?assertEqual(<<"Updated">>, maps:get(name, Result)),
        ?assertEqual(<<"field">>, maps:get(extra, Result)),
        ?assert(is_integer(maps:get(updated_at, Result)))
    end).

test_delete_existing(_DataDir) ->
    MRI = <<"mri:app:io.macula/acme/deletable">>,

    ?_test(begin
        %% Register
        ok = macula_mri_khepri_store:register(?TEST_STORE, MRI, #{}),
        ?assertEqual(true, macula_mri_khepri_store:exists(?TEST_STORE, MRI)),

        %% Delete
        ok = macula_mri_khepri_store:delete(?TEST_STORE, MRI),
        ?assertEqual(false, macula_mri_khepri_store:exists(?TEST_STORE, MRI))
    end).

test_exists_check(_DataDir) ->
    MRI = <<"mri:app:io.macula/acme/checkme">>,

    ?_test(begin
        ?assertEqual(false, macula_mri_khepri_store:exists(?TEST_STORE, MRI)),
        ok = macula_mri_khepri_store:register(?TEST_STORE, MRI, #{}),
        ?assertEqual(true, macula_mri_khepri_store:exists(?TEST_STORE, MRI))
    end).

%%====================================================================
%% Tree Query Tests
%%====================================================================

test_list_children(_DataDir) ->
    Parent = <<"mri:org:io.macula/acme">>,
    Child1 = <<"mri:org:io.macula/acme/team-a">>,
    Child2 = <<"mri:org:io.macula/acme/team-b">>,
    Grandchild = <<"mri:org:io.macula/acme/team-a/member-1">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, Parent, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Child1, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Child2, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Grandchild, #{}),

        Children = macula_mri_khepri_store:list_children(?TEST_STORE, Parent),

        %% Should only include direct children, not grandchildren
        ?assertEqual(2, length(Children)),
        ?assert(lists:member(Child1, Children)),
        ?assert(lists:member(Child2, Children)),
        ?assertNot(lists:member(Grandchild, Children))
    end).

test_list_descendants(_DataDir) ->
    Parent = <<"mri:org:io.macula/corp">>,
    Child = <<"mri:org:io.macula/corp/div">>,
    Grandchild = <<"mri:org:io.macula/corp/div/team">>,
    GreatGrandchild = <<"mri:org:io.macula/corp/div/team/member">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, Parent, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Child, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Grandchild, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, GreatGrandchild, #{}),

        Descendants = macula_mri_khepri_store:list_descendants(?TEST_STORE, Parent),

        %% Should include all descendants
        ?assertEqual(3, length(Descendants)),
        ?assert(lists:member(Child, Descendants)),
        ?assert(lists:member(Grandchild, Descendants)),
        ?assert(lists:member(GreatGrandchild, Descendants))
    end).

test_list_by_type(_DataDir) ->
    App1 = <<"mri:app:io.macula/app1">>,
    App2 = <<"mri:app:io.macula/app2">>,
    Device1 = <<"mri:device:io.macula/dev1">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, App1, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, App2, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Device1, #{}),

        Apps = macula_mri_khepri_store:list_by_type(?TEST_STORE, app, <<"io.macula">>),

        %% Should only include apps in the realm
        ?assertEqual(2, length(Apps)),
        ?assert(lists:member(App1, Apps) orelse lists:member(App2, Apps))
    end).

test_count_children(_DataDir) ->
    Parent = <<"mri:org:io.macula/counted">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, Parent, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, <<"mri:org:io.macula/counted/c1">>, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, <<"mri:org:io.macula/counted/c2">>, #{}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, <<"mri:org:io.macula/counted/c3">>, #{}),

        Count = macula_mri_khepri_store:count_children(?TEST_STORE, Parent),
        ?assertEqual(3, Count)
    end).

%%====================================================================
%% Bulk Operation Tests
%%====================================================================

test_import_multiple(_DataDir) ->
    Entries = [
        {<<"mri:app:io.macula/bulk/a1">>, #{name => <<"App1">>}},
        {<<"mri:app:io.macula/bulk/a2">>, #{name => <<"App2">>}},
        {<<"mri:app:io.macula/bulk/a3">>, #{name => <<"App3">>}}
    ],

    ?_test(begin
        ok = macula_mri_khepri_store:import(?TEST_STORE, Entries),

        %% Verify all were imported
        {ok, R1} = macula_mri_khepri_store:lookup(?TEST_STORE, <<"mri:app:io.macula/bulk/a1">>),
        {ok, R2} = macula_mri_khepri_store:lookup(?TEST_STORE, <<"mri:app:io.macula/bulk/a2">>),
        {ok, R3} = macula_mri_khepri_store:lookup(?TEST_STORE, <<"mri:app:io.macula/bulk/a3">>),

        ?assertEqual(<<"App1">>, maps:get(name, R1)),
        ?assertEqual(<<"App2">>, maps:get(name, R2)),
        ?assertEqual(<<"App3">>, maps:get(name, R3))
    end).

test_export_subtree(_DataDir) ->
    Root = <<"mri:org:io.macula/exported">>,
    Child1 = <<"mri:org:io.macula/exported/c1">>,
    Child2 = <<"mri:org:io.macula/exported/c2">>,

    ?_test(begin
        ok = macula_mri_khepri_store:register(?TEST_STORE, Root, #{name => <<"Root">>}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Child1, #{name => <<"Child1">>}),
        ok = macula_mri_khepri_store:register(?TEST_STORE, Child2, #{name => <<"Child2">>}),

        Exported = macula_mri_khepri_store:export_subtree(?TEST_STORE, Root),

        %% Should export root + children
        ?assertEqual(3, length(Exported)),

        %% Find the root entry
        {Root, RootMeta} = lists:keyfind(Root, 1, Exported),
        ?assertEqual(<<"Root">>, maps:get(name, RootMeta))
    end).

%%====================================================================
%% Graph Relationship Tests
%%====================================================================

test_create_relationship(_DataDir) ->
    Subject = <<"mri:app:io.macula/frontend">>,
    Object = <<"mri:lib:io.macula/utils">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Subject, depends_on, Object, #{}),

        %% Verify relationship exists
        ?assertEqual(true, macula_mri_khepri_graph:relationship_exists(?TEST_STORE, Subject, depends_on, Object))
    end).

test_delete_relationship(_DataDir) ->
    Subject = <<"mri:app:io.macula/delrel-app">>,
    Object = <<"mri:lib:io.macula/delrel-lib">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Subject, depends_on, Object, #{}),
        ?assertEqual(true, macula_mri_khepri_graph:relationship_exists(?TEST_STORE, Subject, depends_on, Object)),

        ok = macula_mri_khepri_graph:delete_relationship(?TEST_STORE, Subject, depends_on, Object),
        ?assertEqual(false, macula_mri_khepri_graph:relationship_exists(?TEST_STORE, Subject, depends_on, Object))
    end).

test_related_to_query(_DataDir) ->
    App = <<"mri:app:io.macula/relto-app">>,
    Lib1 = <<"mri:lib:io.macula/relto-lib1">>,
    Lib2 = <<"mri:lib:io.macula/relto-lib2">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App, depends_on, Lib1, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App, depends_on, Lib2, #{}),

        Related = macula_mri_khepri_graph:related_to(?TEST_STORE, App, depends_on),

        ?assertEqual(2, length(Related)),
        ?assert(lists:member(Lib1, Related)),
        ?assert(lists:member(Lib2, Related))
    end).

test_related_from_query(_DataDir) ->
    Lib = <<"mri:lib:io.macula/common">>,
    App1 = <<"mri:app:io.macula/relfrom-app1">>,
    App2 = <<"mri:app:io.macula/relfrom-app2">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App1, depends_on, Lib, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App2, depends_on, Lib, #{}),

        Dependents = macula_mri_khepri_graph:related_from(?TEST_STORE, Lib, depends_on),

        ?assertEqual(2, length(Dependents)),
        ?assert(lists:member(App1, Dependents)),
        ?assert(lists:member(App2, Dependents))
    end).

test_all_related(_DataDir) ->
    App = <<"mri:app:io.macula/allrel-app">>,
    Lib = <<"mri:lib:io.macula/allrel-lib">>,
    Loc = <<"mri:location:io.macula/allrel-loc">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App, depends_on, Lib, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, App, deployed_at, Loc, #{}),

        AllRel = macula_mri_khepri_graph:all_related(?TEST_STORE, App),

        ?assertEqual(2, length(AllRel)),
        ?assert(lists:member({depends_on, Lib}, AllRel)),
        ?assert(lists:member({deployed_at, Loc}, AllRel))
    end).

test_traverse_single_hop(_DataDir) ->
    A = <<"mri:node:io.macula/hop-a">>,
    B = <<"mri:node:io.macula/hop-b">>,
    C = <<"mri:node:io.macula/hop-c">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, A, connects_to, B, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, B, connects_to, C, #{}),

        %% Forward from A
        ForwardA = macula_mri_khepri_graph:traverse(?TEST_STORE, A, connects_to, forward),
        ?assertEqual([B], ForwardA),

        %% Reverse from C
        ReverseC = macula_mri_khepri_graph:traverse(?TEST_STORE, C, connects_to, reverse),
        ?assertEqual([B], ReverseC)
    end).

test_traverse_transitive(_DataDir) ->
    Root = <<"mri:node:io.macula/trans-root">>,
    Mid = <<"mri:node:io.macula/trans-mid">>,
    Leaf = <<"mri:node:io.macula/trans-leaf">>,

    ?_test(begin
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Root, parent_of, Mid, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Mid, parent_of, Leaf, #{}),

        %% Transitive forward traversal
        All = macula_mri_khepri_graph:traverse_transitive(?TEST_STORE, Root, parent_of, forward),

        ?assertEqual(2, length(All)),
        ?assert(lists:member(Mid, All)),
        ?assert(lists:member(Leaf, All))
    end).

test_traverse_with_cycles(_DataDir) ->
    A = <<"mri:node:io.macula/cycle-a">>,
    B = <<"mri:node:io.macula/cycle-b">>,
    C = <<"mri:node:io.macula/cycle-c">>,

    ?_test(begin
        %% Create a cycle: A -> B -> C -> A
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, A, links_to, B, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, B, links_to, C, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, C, links_to, A, #{}),

        %% Transitive traversal should handle cycles
        Result = macula_mri_khepri_graph:traverse_transitive(?TEST_STORE, A, links_to, forward),

        %% Should find B and C (but not revisit A due to cycle detection)
        ?assertEqual(2, length(Result)),
        ?assert(lists:member(B, Result)),
        ?assert(lists:member(C, Result))
    end).

%%====================================================================
%% Taxonomy Tests
%%====================================================================

test_instances_of(_DataDir) ->
    Class = <<"mri:class:io.macula/sensor">>,
    Inst1 = <<"mri:device:io.macula/sensor-001">>,
    Inst2 = <<"mri:device:io.macula/sensor-002">>,

    ?_test(begin
        %% Create instance relationships
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Inst1, instance_of, Class, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Inst2, instance_of, Class, #{}),

        Instances = macula_mri_khepri_graph:instances_of(?TEST_STORE, Class),

        ?assertEqual(2, length(Instances)),
        ?assert(lists:member(Inst1, Instances)),
        ?assert(lists:member(Inst2, Instances))
    end).

test_instances_of_transitive(_DataDir) ->
    BaseClass = <<"mri:class:io.macula/equipment">>,
    SubClass = <<"mri:class:io.macula/sensor-type">>,
    DirectInst = <<"mri:device:io.macula/direct-equip">>,
    SubInst = <<"mri:device:io.macula/sensor-inst">>,

    ?_test(begin
        %% Class hierarchy: SubClass is subclass_of BaseClass
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, SubClass, subclass_of, BaseClass, #{}),

        %% Instances
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, DirectInst, instance_of, BaseClass, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, SubInst, instance_of, SubClass, #{}),

        %% Transitive should find both direct and indirect instances
        AllInstances = macula_mri_khepri_graph:instances_of_transitive(?TEST_STORE, BaseClass),

        ?assert(lists:member(DirectInst, AllInstances)),
        ?assert(lists:member(SubInst, AllInstances))
    end).

test_class_hierarchy(_DataDir) ->
    GrandParent = <<"mri:class:io.macula/entity">>,
    Parent = <<"mri:class:io.macula/resource">>,
    Child = <<"mri:class:io.macula/compute-resource">>,

    ?_test(begin
        %% Build hierarchy
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Parent, subclass_of, GrandParent, #{}),
        ok = macula_mri_khepri_graph:create_relationship(?TEST_STORE, Child, subclass_of, Parent, #{}),

        %% Test superclasses
        ParentSupers = macula_mri_khepri_graph:superclasses(?TEST_STORE, Parent),
        ?assertEqual([GrandParent], ParentSupers),

        ChildSupers = macula_mri_khepri_graph:superclasses(?TEST_STORE, Child),
        ?assertEqual([Parent], ChildSupers),

        %% Test subclasses
        GrandParentSubs = macula_mri_khepri_graph:subclasses(?TEST_STORE, GrandParent),
        ?assertEqual([Parent], GrandParentSubs),

        ParentSubs = macula_mri_khepri_graph:subclasses(?TEST_STORE, Parent),
        ?assertEqual([Child], ParentSubs)
    end).
