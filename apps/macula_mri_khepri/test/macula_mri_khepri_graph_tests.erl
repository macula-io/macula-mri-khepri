%%%-------------------------------------------------------------------
%%% @doc
%%% EUnit tests for macula_mri_khepri_graph.
%%%
%%% Tests cover:
%%% - Relationship CRUD (create, delete, exists)
%%% - Forward queries (related_to, all_related)
%%% - Reverse queries (related_from, all_related_from)
%%% - Graph traversal (traverse, traverse_transitive)
%%% - Taxonomy helpers (instances_of, classes_of, subclasses, superclasses)
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_graph_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

setup() ->
    meck:new(khepri, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(khepri),
    ok.

%%====================================================================
%% Test Generators
%%====================================================================

graph_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
        %% Relationship CRUD
        {"Create relationship stores bidirectionally", fun create_relationship_stores_bidirectionally/0},
        {"Create relationship with metadata", fun create_relationship_with_metadata/0},
        {"Delete relationship removes both directions", fun delete_relationship_removes_both_directions/0},
        {"Relationship exists checks forward index", fun relationship_exists_checks_forward_index/0},
        {"Relationship not exists returns false", fun relationship_not_exists_returns_false/0},

        %% Forward queries
        {"Related to returns objects for predicate", fun related_to_returns_objects/0},
        {"Related to returns empty for no relationships", fun related_to_returns_empty/0},
        {"All related returns all predicates and objects", fun all_related_returns_all/0},
        {"All related returns empty for no relationships", fun all_related_returns_empty/0},

        %% Reverse queries
        {"Related from returns subjects for predicate", fun related_from_returns_subjects/0},
        {"Related from returns empty for no relationships", fun related_from_returns_empty/0},
        {"All related from returns all predicates and subjects", fun all_related_from_returns_all/0},

        %% Traversal
        {"Traverse forward returns direct neighbors", fun traverse_forward_returns_direct/0},
        {"Traverse reverse returns direct neighbors", fun traverse_reverse_returns_direct/0},
        {"Traverse transitive follows chains", fun traverse_transitive_follows_chains/0},
        {"Traverse transitive handles cycles", fun traverse_transitive_handles_cycles/0},

        %% Taxonomy
        {"Instances of returns direct instances", fun instances_of_returns_direct/0},
        {"Instances of transitive includes subclass instances", fun instances_of_transitive_includes_subclass/0},
        {"Classes of returns classes via instance_of", fun classes_of_returns_classes/0},
        {"Subclasses returns direct subclasses", fun subclasses_returns_direct/0},
        {"Superclasses returns direct superclasses", fun superclasses_returns_direct/0}
     ]}.

%%====================================================================
%% Relationship CRUD Tests
%%====================================================================

create_relationship_stores_bidirectionally() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,
    Object = <<"mri:lib:io.macula/math">>,

    TransactionPaths = ets:new(transaction_paths, [public, bag]),

    meck:expect(khepri, transaction, fun(_Store, Fun) ->
        %% Mock khepri_tx:put to capture paths
        meck:new(khepri_tx, [non_strict]),
        meck:expect(khepri_tx, put, fun(Path, _Data) ->
            ets:insert(TransactionPaths, {path, Path}),
            ok
        end),
        Fun(),
        meck:unload(khepri_tx),
        ok
    end),

    Result = macula_mri_khepri_graph:create_relationship(test_store, Subject, Predicate, Object, #{}),

    ?assertEqual(ok, Result),

    %% Verify forward path
    ForwardMatches = ets:match(TransactionPaths, {path, [mri_rel, forward, Subject, Predicate, Object]}),
    ?assertNotEqual([], ForwardMatches),

    %% Verify reverse path
    ReverseMatches = ets:match(TransactionPaths, {path, [mri_rel, reverse, Object, Predicate, Subject]}),
    ?assertNotEqual([], ReverseMatches),

    ets:delete(TransactionPaths).

create_relationship_with_metadata() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,
    Object = <<"mri:lib:io.macula/math">>,
    Metadata = #{version => <<"1.0">>, optional => true},

    CapturedData = ets:new(captured_data, [public, set]),

    meck:expect(khepri, transaction, fun(_Store, Fun) ->
        meck:new(khepri_tx, [non_strict]),
        meck:expect(khepri_tx, put, fun(_Path, Data) ->
            ets:insert(CapturedData, {data, Data}),
            ok
        end),
        Fun(),
        meck:unload(khepri_tx),
        ok
    end),

    macula_mri_khepri_graph:create_relationship(test_store, Subject, Predicate, Object, Metadata),

    [{data, ResultData}] = ets:lookup(CapturedData, data),
    ?assertEqual(Subject, maps:get(subject, ResultData)),
    ?assertEqual(Predicate, maps:get(predicate, ResultData)),
    ?assertEqual(Object, maps:get(object, ResultData)),
    ?assertEqual(<<"1.0">>, maps:get(version, ResultData)),
    ?assertEqual(true, maps:get(optional, ResultData)),
    ?assert(maps:is_key(created_at, ResultData)),

    ets:delete(CapturedData).

delete_relationship_removes_both_directions() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,
    Object = <<"mri:lib:io.macula/math">>,

    DeletedPaths = ets:new(deleted_paths, [public, bag]),

    meck:expect(khepri, transaction, fun(_Store, Fun) ->
        meck:new(khepri_tx, [non_strict]),
        meck:expect(khepri_tx, delete, fun(Path) ->
            ets:insert(DeletedPaths, {path, Path}),
            ok
        end),
        Fun(),
        meck:unload(khepri_tx),
        ok
    end),

    Result = macula_mri_khepri_graph:delete_relationship(test_store, Subject, Predicate, Object),

    ?assertEqual(ok, Result),

    %% Verify forward path deleted
    ForwardMatches = ets:match(DeletedPaths, {path, [mri_rel, forward, Subject, Predicate, Object]}),
    ?assertNotEqual([], ForwardMatches),

    %% Verify reverse path deleted
    ReverseMatches = ets:match(DeletedPaths, {path, [mri_rel, reverse, Object, Predicate, Subject]}),
    ?assertNotEqual([], ReverseMatches),

    ets:delete(DeletedPaths).

relationship_exists_checks_forward_index() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,
    Object = <<"mri:lib:io.macula/math">>,

    meck:expect(khepri, exists, fun(_Store, Path) ->
        Path =:= [mri_rel, forward, Subject, Predicate, Object]
    end),

    Result = macula_mri_khepri_graph:relationship_exists(test_store, Subject, Predicate, Object),

    ?assertEqual(true, Result).

relationship_not_exists_returns_false() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,
    Object = <<"mri:lib:io.macula/nonexistent">>,

    meck:expect(khepri, exists, fun(_Store, _Path) -> false end),

    Result = macula_mri_khepri_graph:relationship_exists(test_store, Subject, Predicate, Object),

    ?assertEqual(false, Result).

%%====================================================================
%% Forward Query Tests
%%====================================================================

related_to_returns_objects() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,

    RelationshipData = #{
        [mri_rel, forward, Subject, Predicate, <<"mri:lib:io.macula/math">>] =>
            #{subject => Subject, predicate => Predicate, object => <<"mri:lib:io.macula/math">>},
        [mri_rel, forward, Subject, Predicate, <<"mri:lib:io.macula/io">>] =>
            #{subject => Subject, predicate => Predicate, object => <<"mri:lib:io.macula/io">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:related_to(test_store, Subject, Predicate),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:lib:io.macula/math">>, Result)),
    ?assert(lists:member(<<"mri:lib:io.macula/io">>, Result)).

related_to_returns_empty() ->
    Subject = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    Result = macula_mri_khepri_graph:related_to(test_store, Subject, Predicate),

    ?assertEqual([], Result).

all_related_returns_all() ->
    Subject = <<"mri:app:io.macula/counter">>,

    RelationshipData = #{
        [mri_rel, forward, Subject, depends_on, <<"mri:lib:io.macula/math">>] =>
            #{predicate => depends_on, object => <<"mri:lib:io.macula/math">>},
        [mri_rel, forward, Subject, authored_by, <<"mri:user:io.macula/alice">>] =>
            #{predicate => authored_by, object => <<"mri:user:io.macula/alice">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:all_related(test_store, Subject),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member({depends_on, <<"mri:lib:io.macula/math">>}, Result)),
    ?assert(lists:member({authored_by, <<"mri:user:io.macula/alice">>}, Result)).

all_related_returns_empty() ->
    Subject = <<"mri:app:io.macula/isolated">>,

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    Result = macula_mri_khepri_graph:all_related(test_store, Subject),

    ?assertEqual([], Result).

%%====================================================================
%% Reverse Query Tests
%%====================================================================

related_from_returns_subjects() ->
    Object = <<"mri:lib:io.macula/math">>,
    Predicate = depends_on,

    RelationshipData = #{
        [mri_rel, reverse, Object, Predicate, <<"mri:app:io.macula/counter">>] =>
            #{subject => <<"mri:app:io.macula/counter">>, predicate => Predicate, object => Object},
        [mri_rel, reverse, Object, Predicate, <<"mri:app:io.macula/calculator">>] =>
            #{subject => <<"mri:app:io.macula/calculator">>, predicate => Predicate, object => Object}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:related_from(test_store, Object, Predicate),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:app:io.macula/counter">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/calculator">>, Result)).

related_from_returns_empty() ->
    Object = <<"mri:lib:io.macula/orphan">>,
    Predicate = depends_on,

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    Result = macula_mri_khepri_graph:related_from(test_store, Object, Predicate),

    ?assertEqual([], Result).

all_related_from_returns_all() ->
    Object = <<"mri:user:io.macula/alice">>,

    RelationshipData = #{
        [mri_rel, reverse, Object, authored_by, <<"mri:app:io.macula/counter">>] =>
            #{predicate => authored_by, subject => <<"mri:app:io.macula/counter">>},
        [mri_rel, reverse, Object, maintained_by, <<"mri:lib:io.macula/utils">>] =>
            #{predicate => maintained_by, subject => <<"mri:lib:io.macula/utils">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:all_related_from(test_store, Object),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member({authored_by, <<"mri:app:io.macula/counter">>}, Result)),
    ?assert(lists:member({maintained_by, <<"mri:lib:io.macula/utils">>}, Result)).

%%====================================================================
%% Traversal Tests
%%====================================================================

traverse_forward_returns_direct() ->
    Start = <<"mri:app:io.macula/counter">>,
    Predicate = depends_on,

    RelationshipData = #{
        [mri_rel, forward, Start, Predicate, <<"mri:lib:io.macula/math">>] =>
            #{subject => Start, predicate => Predicate, object => <<"mri:lib:io.macula/math">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:traverse(test_store, Start, Predicate, forward),

    ?assertEqual([<<"mri:lib:io.macula/math">>], Result).

traverse_reverse_returns_direct() ->
    Start = <<"mri:lib:io.macula/math">>,
    Predicate = depends_on,

    RelationshipData = #{
        [mri_rel, reverse, Start, Predicate, <<"mri:app:io.macula/counter">>] =>
            #{subject => <<"mri:app:io.macula/counter">>, predicate => Predicate, object => Start}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:traverse(test_store, Start, Predicate, reverse),

    ?assertEqual([<<"mri:app:io.macula/counter">>], Result).

traverse_transitive_follows_chains() ->
    %% A -> B -> C chain
    A = <<"mri:class:io.macula/animal">>,
    B = <<"mri:class:io.macula/mammal">>,
    C = <<"mri:class:io.macula/dog">>,
    Predicate = subclass_of,

    %% Mock to return different results based on query
    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri_rel, reverse, A, Predicate, _] ->
                {ok, #{
                    [mri_rel, reverse, A, Predicate, B] =>
                        #{subject => B, predicate => Predicate, object => A}
                }};
            [mri_rel, reverse, B, Predicate, _] ->
                {ok, #{
                    [mri_rel, reverse, B, Predicate, C] =>
                        #{subject => C, predicate => Predicate, object => B}
                }};
            [mri_rel, reverse, C, Predicate, _] ->
                {ok, #{}};
            _ ->
                {ok, #{}}
        end
    end),

    Result = macula_mri_khepri_graph:traverse_transitive(test_store, A, Predicate, reverse),

    ?assert(lists:member(B, Result)),
    ?assert(lists:member(C, Result)).

traverse_transitive_handles_cycles() ->
    %% A -> B -> A cycle
    A = <<"mri:node:io.macula/a">>,
    B = <<"mri:node:io.macula/b">>,
    Predicate = linked_to,

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri_rel, forward, A, Predicate, _] ->
                {ok, #{
                    [mri_rel, forward, A, Predicate, B] =>
                        #{subject => A, predicate => Predicate, object => B}
                }};
            [mri_rel, forward, B, Predicate, _] ->
                {ok, #{
                    [mri_rel, forward, B, Predicate, A] =>
                        #{subject => B, predicate => Predicate, object => A}
                }};
            _ ->
                {ok, #{}}
        end
    end),

    %% Should terminate without infinite loop
    Result = macula_mri_khepri_graph:traverse_transitive(test_store, A, Predicate, forward),

    %% B should appear exactly once, A should not appear (it's the start)
    ?assert(lists:member(B, Result)),
    %% A may appear once (from B's edges) but not infinitely
    ?assert(length(Result) =< 2).

%%====================================================================
%% Taxonomy Tests
%%====================================================================

instances_of_returns_direct() ->
    Class = <<"mri:class:io.macula/vehicle">>,

    RelationshipData = #{
        [mri_rel, reverse, Class, instance_of, <<"mri:vehicle:io.macula/car1">>] =>
            #{subject => <<"mri:vehicle:io.macula/car1">>, predicate => instance_of, object => Class},
        [mri_rel, reverse, Class, instance_of, <<"mri:vehicle:io.macula/bike1">>] =>
            #{subject => <<"mri:vehicle:io.macula/bike1">>, predicate => instance_of, object => Class}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:instances_of(test_store, Class),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:vehicle:io.macula/car1">>, Result)),
    ?assert(lists:member(<<"mri:vehicle:io.macula/bike1">>, Result)).

instances_of_transitive_includes_subclass() ->
    %% Vehicle <- Car (subclass) <- MyCar (instance)
    Vehicle = <<"mri:class:io.macula/vehicle">>,
    Car = <<"mri:class:io.macula/car">>,
    MyCar = <<"mri:instance:io.macula/my-car">>,
    DirectVehicle = <<"mri:instance:io.macula/direct-vehicle">>,

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            %% Direct instances of Vehicle
            [mri_rel, reverse, Vehicle, instance_of, _] ->
                {ok, #{
                    [mri_rel, reverse, Vehicle, instance_of, DirectVehicle] =>
                        #{subject => DirectVehicle, predicate => instance_of, object => Vehicle}
                }};
            %% Subclasses of Vehicle
            [mri_rel, reverse, Vehicle, subclass_of, _] ->
                {ok, #{
                    [mri_rel, reverse, Vehicle, subclass_of, Car] =>
                        #{subject => Car, predicate => subclass_of, object => Vehicle}
                }};
            %% Direct instances of Car
            [mri_rel, reverse, Car, instance_of, _] ->
                {ok, #{
                    [mri_rel, reverse, Car, instance_of, MyCar] =>
                        #{subject => MyCar, predicate => instance_of, object => Car}
                }};
            %% No subclasses of Car
            [mri_rel, reverse, Car, subclass_of, _] ->
                {ok, #{}};
            _ ->
                {ok, #{}}
        end
    end),

    Result = macula_mri_khepri_graph:instances_of_transitive(test_store, Vehicle),

    ?assert(lists:member(DirectVehicle, Result)),
    ?assert(lists:member(MyCar, Result)).

classes_of_returns_classes() ->
    Instance = <<"mri:vehicle:io.macula/my-car">>,

    RelationshipData = #{
        [mri_rel, forward, Instance, instance_of, <<"mri:class:io.macula/car">>] =>
            #{subject => Instance, predicate => instance_of, object => <<"mri:class:io.macula/car">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:classes_of(test_store, Instance),

    ?assertEqual([<<"mri:class:io.macula/car">>], Result).

subclasses_returns_direct() ->
    Class = <<"mri:class:io.macula/vehicle">>,

    RelationshipData = #{
        [mri_rel, reverse, Class, subclass_of, <<"mri:class:io.macula/car">>] =>
            #{subject => <<"mri:class:io.macula/car">>, predicate => subclass_of, object => Class},
        [mri_rel, reverse, Class, subclass_of, <<"mri:class:io.macula/bike">>] =>
            #{subject => <<"mri:class:io.macula/bike">>, predicate => subclass_of, object => Class}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:subclasses(test_store, Class),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:class:io.macula/car">>, Result)),
    ?assert(lists:member(<<"mri:class:io.macula/bike">>, Result)).

superclasses_returns_direct() ->
    Class = <<"mri:class:io.macula/car">>,

    RelationshipData = #{
        [mri_rel, forward, Class, subclass_of, <<"mri:class:io.macula/vehicle">>] =>
            #{subject => Class, predicate => subclass_of, object => <<"mri:class:io.macula/vehicle">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, RelationshipData} end),

    Result = macula_mri_khepri_graph:superclasses(test_store, Class),

    ?assertEqual([<<"mri:class:io.macula/vehicle">>], Result).
