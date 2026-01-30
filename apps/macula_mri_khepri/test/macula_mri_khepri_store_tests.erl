%%%-------------------------------------------------------------------
%%% @doc
%%% EUnit tests for macula_mri_khepri_store.
%%%
%%% Tests cover:
%%% - CRUD operations (register, lookup, update, delete, exists)
%%% - Tree queries (list_children, list_descendants, list_by_type, count_children)
%%% - Bulk operations (import, export_subtree)
%%% - Error handling and edge cases
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_store_tests).

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

store_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
        {"Register new MRI succeeds", fun register_new_mri_succeeds/0},
        {"Register existing MRI fails", fun register_existing_mri_fails/0},
        {"Register updates indexes", fun register_updates_indexes/0},
        {"Lookup existing MRI returns metadata", fun lookup_existing_returns_metadata/0},
        {"Lookup non-existent MRI returns not_found", fun lookup_nonexistent_returns_not_found/0},
        {"Update existing MRI succeeds", fun update_existing_succeeds/0},
        {"Update non-existent MRI fails", fun update_nonexistent_fails/0},
        {"Update merges metadata", fun update_merges_metadata/0},
        {"Delete existing MRI succeeds", fun delete_existing_succeeds/0},
        {"Delete non-existent MRI fails", fun delete_nonexistent_fails/0},
        {"Delete removes indexes", fun delete_removes_indexes/0},
        {"Exists returns true for existing MRI", fun exists_returns_true_for_existing/0},
        {"Exists returns false for non-existent MRI", fun exists_returns_false_for_nonexistent/0},
        {"List children returns direct children only", fun list_children_returns_direct_only/0},
        {"List children returns empty for leaf MRI", fun list_children_returns_empty_for_leaf/0},
        {"List descendants returns all nested MRIs", fun list_descendants_returns_all_nested/0},
        {"List descendants returns empty for leaf MRI", fun list_descendants_returns_empty_for_leaf/0},
        {"List by type uses index", fun list_by_type_uses_index/0},
        {"List by type falls back to direct query", fun list_by_type_fallback/0},
        {"Count children returns correct count", fun count_children_returns_correct_count/0},
        {"Import creates multiple MRIs atomically", fun import_creates_multiple_atomically/0},
        {"Export subtree includes all descendants", fun export_subtree_includes_all/0},
        %% Pagination tests
        {"List children with limit", fun list_children_with_limit/0},
        {"List children with offset", fun list_children_with_offset/0},
        {"List descendants with pagination", fun list_descendants_with_pagination/0},
        {"List by type with pagination", fun list_by_type_with_pagination/0}
     ]}.

%%====================================================================
%% CRUD Tests
%%====================================================================

register_new_mri_succeeds() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    Metadata = #{name => <<"Counter App">>},

    meck:expect(khepri, create, fun(_Store, _Path, _Data) -> ok end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    Result = macula_mri_khepri_store:register(test_store, MRI, Metadata),

    ?assertEqual(ok, Result),
    ?assert(meck:called(khepri, create, '_')).

register_existing_mri_fails() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    Metadata = #{name => <<"Counter App">>},

    meck:expect(khepri, create, fun(_Store, _Path, _Data) ->
        {error, {mismatching_node, existing_data}}
    end),

    Result = macula_mri_khepri_store:register(test_store, MRI, Metadata),

    ?assertEqual({error, already_exists}, Result).

register_updates_indexes() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    Metadata = #{name => <<"Counter App">>},

    PutCalls = ets:new(put_calls, [public, bag]),

    meck:expect(khepri, create, fun(_Store, _Path, _Data) -> ok end),
    meck:expect(khepri, put, fun(_Store, Path, _Data) ->
        ets:insert(PutCalls, {Path}),
        ok
    end),

    macula_mri_khepri_store:register(test_store, MRI, Metadata),

    %% Verify type index was updated
    TypeIndexCalls = ets:match(PutCalls, {[mri_index, by_type, app, <<"io.macula">>, MRI]}),
    ?assertNotEqual([], TypeIndexCalls),

    %% Verify realm index was updated
    RealmIndexCalls = ets:match(PutCalls, {[mri_index, by_realm, <<"io.macula">>, MRI]}),
    ?assertNotEqual([], RealmIndexCalls),

    ets:delete(PutCalls).

lookup_existing_returns_metadata() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    ExpectedMeta = #{mri => MRI, name => <<"Counter App">>},

    meck:expect(khepri, get, fun(_Store, _Path) -> {ok, ExpectedMeta} end),

    Result = macula_mri_khepri_store:lookup(test_store, MRI),

    ?assertEqual({ok, ExpectedMeta}, Result).

lookup_nonexistent_returns_not_found() ->
    MRI = <<"mri:app:io.macula/nonexistent">>,

    meck:expect(khepri, get, fun(_Store, _Path) ->
        {error, {node_not_found, some_path}}
    end),

    Result = macula_mri_khepri_store:lookup(test_store, MRI),

    ?assertEqual({error, not_found}, Result).

update_existing_succeeds() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    ExistingMeta = #{mri => MRI, name => <<"Old Name">>},
    NewMeta = #{name => <<"New Name">>},

    meck:expect(khepri, get, fun(_Store, _Path) -> {ok, ExistingMeta} end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    Result = macula_mri_khepri_store:update(test_store, MRI, NewMeta),

    ?assertEqual(ok, Result).

update_nonexistent_fails() ->
    MRI = <<"mri:app:io.macula/nonexistent">>,
    NewMeta = #{name => <<"New Name">>},

    meck:expect(khepri, get, fun(_Store, _Path) ->
        {error, {node_not_found, some_path}}
    end),

    Result = macula_mri_khepri_store:update(test_store, MRI, NewMeta),

    ?assertEqual({error, not_found}, Result).

update_merges_metadata() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,
    ExistingMeta = #{mri => MRI, name => <<"App">>, version => <<"1.0">>},
    NewMeta = #{name => <<"Updated App">>},

    CapturedData = ets:new(captured_data, [public, set]),

    meck:expect(khepri, get, fun(_Store, _Path) -> {ok, ExistingMeta} end),
    meck:expect(khepri, put, fun(_Store, _Path, Data) ->
        ets:insert(CapturedData, {data, Data}),
        ok
    end),

    macula_mri_khepri_store:update(test_store, MRI, NewMeta),

    [{data, ResultData}] = ets:lookup(CapturedData, data),
    ?assertEqual(<<"Updated App">>, maps:get(name, ResultData)),
    ?assertEqual(<<"1.0">>, maps:get(version, ResultData)),
    ?assert(maps:is_key(updated_at, ResultData)),

    ets:delete(CapturedData).

delete_existing_succeeds() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,

    meck:expect(khepri, delete, fun(_Store, _Path) -> ok end),

    Result = macula_mri_khepri_store:delete(test_store, MRI),

    ?assertEqual(ok, Result).

delete_nonexistent_fails() ->
    MRI = <<"mri:app:io.macula/nonexistent">>,

    meck:expect(khepri, delete, fun(_Store, _Path) ->
        {error, {node_not_found, some_path}}
    end),

    Result = macula_mri_khepri_store:delete(test_store, MRI),

    ?assertEqual({error, not_found}, Result).

delete_removes_indexes() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,

    DeleteCalls = ets:new(delete_calls, [public, bag]),

    meck:expect(khepri, delete, fun(_Store, Path) ->
        ets:insert(DeleteCalls, {Path}),
        ok
    end),

    macula_mri_khepri_store:delete(test_store, MRI),

    %% Verify type index was deleted
    TypeIndexCalls = ets:match(DeleteCalls, {[mri_index, by_type, app, <<"io.macula">>, MRI]}),
    ?assertNotEqual([], TypeIndexCalls),

    %% Verify realm index was deleted
    RealmIndexCalls = ets:match(DeleteCalls, {[mri_index, by_realm, <<"io.macula">>, MRI]}),
    ?assertNotEqual([], RealmIndexCalls),

    ets:delete(DeleteCalls).

exists_returns_true_for_existing() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,

    meck:expect(khepri, exists, fun(_Store, _Path) -> true end),

    Result = macula_mri_khepri_store:exists(test_store, MRI),

    ?assertEqual(true, Result).

exists_returns_false_for_nonexistent() ->
    MRI = <<"mri:app:io.macula/nonexistent">>,

    meck:expect(khepri, exists, fun(_Store, _Path) -> false end),

    Result = macula_mri_khepri_store:exists(test_store, MRI),

    ?assertEqual(false, Result).

%%====================================================================
%% Tree Query Tests
%%====================================================================

list_children_returns_direct_only() ->
    MRI = <<"mri:app:io.macula/acme">>,

    ChildData = #{
        [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/acme/counter">>},
        [mri, app, <<"io.macula">>, <<"acme">>, <<"timer">>] =>
            #{mri => <<"mri:app:io.macula/acme/timer">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, ChildData} end),

    Result = macula_mri_khepri_store:list_children(test_store, MRI),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:app:io.macula/acme/counter">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/acme/timer">>, Result)).

list_children_returns_empty_for_leaf() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    Result = macula_mri_khepri_store:list_children(test_store, MRI),

    ?assertEqual([], Result).

list_descendants_returns_all_nested() ->
    MRI = <<"mri:app:io.macula">>,

    DescendantData = #{
        [mri, app, <<"io.macula">>, <<"acme">>] =>
            #{mri => <<"mri:app:io.macula/acme">>},
        [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/acme/counter">>},
        [mri, app, <<"io.macula">>, <<"acme">>, <<"timer">>] =>
            #{mri => <<"mri:app:io.macula/acme/timer">>},
        [mri, app, <<"io.macula">>, <<"corp">>] =>
            #{mri => <<"mri:app:io.macula/corp">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, DescendantData} end),

    Result = macula_mri_khepri_store:list_descendants(test_store, MRI),

    ?assertEqual(4, length(Result)),
    ?assert(lists:member(<<"mri:app:io.macula/acme">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/acme/counter">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/acme/timer">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/corp">>, Result)).

list_descendants_returns_empty_for_leaf() ->
    MRI = <<"mri:app:io.macula/acme/counter">>,

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, #{}} end),

    Result = macula_mri_khepri_store:list_descendants(test_store, MRI),

    ?assertEqual([], Result).

list_by_type_uses_index() ->
    Type = app,
    Realm = <<"io.macula">>,

    IndexData = #{
        <<"mri:app:io.macula/counter">> => true,
        <<"mri:app:io.macula/timer">> => true
    },

    meck:expect(khepri, get_many, fun(_Store, [mri_index, by_type | _]) ->
        {ok, IndexData}
    end),

    Result = macula_mri_khepri_store:list_by_type(test_store, Type, Realm),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:app:io.macula/counter">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/timer">>, Result)).

list_by_type_fallback() ->
    Type = app,
    Realm = <<"io.macula">>,

    DirectData = #{
        [mri, app, <<"io.macula">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/counter">>},
        [mri, app, <<"io.macula">>, <<"timer">>] =>
            #{mri => <<"mri:app:io.macula/timer">>}
    },

    meck:expect(khepri, get_many, fun(_Store, Path) ->
        case Path of
            [mri_index, by_type | _] -> {error, {node_not_found, some_path}};
            [mri, app, _Realm | _] -> {ok, DirectData}
        end
    end),

    Result = macula_mri_khepri_store:list_by_type(test_store, Type, Realm),

    ?assertEqual(2, length(Result)),
    ?assert(lists:member(<<"mri:app:io.macula/counter">>, Result)),
    ?assert(lists:member(<<"mri:app:io.macula/timer">>, Result)).

count_children_returns_correct_count() ->
    MRI = <<"mri:app:io.macula/acme">>,

    ChildData = #{
        [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/acme/counter">>},
        [mri, app, <<"io.macula">>, <<"acme">>, <<"timer">>] =>
            #{mri => <<"mri:app:io.macula/acme/timer">>},
        [mri, app, <<"io.macula">>, <<"acme">>, <<"clock">>] =>
            #{mri => <<"mri:app:io.macula/acme/clock">>}
    },

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, ChildData} end),

    Result = macula_mri_khepri_store:count_children(test_store, MRI),

    ?assertEqual(3, Result).

%%====================================================================
%% Bulk Operation Tests
%%====================================================================

import_creates_multiple_atomically() ->
    Entries = [
        {<<"mri:app:io.macula/counter">>, #{name => <<"Counter">>}},
        {<<"mri:app:io.macula/timer">>, #{name => <<"Timer">>}}
    ],

    meck:expect(khepri, transaction, fun(_Store, Fun) ->
        %% Simply verify the transaction function is valid
        ?assert(is_function(Fun, 0)),
        ok
    end),

    Result = macula_mri_khepri_store:import(test_store, Entries),

    ?assertEqual(ok, Result),
    ?assert(meck:called(khepri, transaction, '_')).

export_subtree_includes_all() ->
    MRI = <<"mri:app:io.macula/acme">>,

    DescendantData = #{
        [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>] =>
            #{mri => <<"mri:app:io.macula/acme/counter">>}
    },

    AcmeData = #{mri => MRI, name => <<"Acme">>},
    CounterData = #{mri => <<"mri:app:io.macula/acme/counter">>, name => <<"Counter">>},

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, DescendantData} end),
    meck:expect(khepri, get, fun(_Store, Path) ->
        case Path of
            [mri, app, <<"io.macula">>, <<"acme">>] -> {ok, AcmeData};
            [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>] -> {ok, CounterData}
        end
    end),

    Result = macula_mri_khepri_store:export_subtree(test_store, MRI),

    ?assertEqual(2, length(Result)),
    ?assert(lists:keymember(MRI, 1, Result)),
    ?assert(lists:keymember(<<"mri:app:io.macula/acme/counter">>, 1, Result)).

%%====================================================================
%% MRI Parsing Edge Cases
%%====================================================================

parse_mri_test_() ->
    [
        {"Valid MRI with path segments", fun parse_valid_mri_with_path/0},
        {"Valid MRI without path", fun parse_valid_mri_without_path/0},
        {"MRI with multiple path segments", fun parse_mri_multiple_segments/0}
    ].

parse_valid_mri_with_path() ->
    %% Test register to verify mri_to_path works
    MRI = <<"mri:device:io.telcox.be/cabinet/1234">>,
    Metadata = #{name => <<"Cabinet 1234">>},

    CapturedPath = ets:new(captured_path, [public, set]),

    meck:expect(khepri, create, fun(_Store, Path, _Data) ->
        ets:insert(CapturedPath, {path, Path}),
        ok
    end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    macula_mri_khepri_store:register(test_store, MRI, Metadata),

    [{path, ResultPath}] = ets:lookup(CapturedPath, path),
    ?assertEqual([mri, device, <<"io.telcox.be">>, <<"cabinet">>, <<"1234">>], ResultPath),

    ets:delete(CapturedPath).

parse_valid_mri_without_path() ->
    %% MRI with realm only (no path segments)
    MRI = <<"mri:realm:io.macula">>,
    Metadata = #{name => <<"Macula Realm">>},

    CapturedPath = ets:new(captured_path, [public, set]),

    meck:expect(khepri, create, fun(_Store, Path, _Data) ->
        ets:insert(CapturedPath, {path, Path}),
        ok
    end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    macula_mri_khepri_store:register(test_store, MRI, Metadata),

    [{path, ResultPath}] = ets:lookup(CapturedPath, path),
    ?assertEqual([mri, realm, <<"io.macula">>], ResultPath),

    ets:delete(CapturedPath).

parse_mri_multiple_segments() ->
    %% MRI with deeply nested path
    MRI = <<"mri:asset:io.macula/org/team/project/asset">>,
    Metadata = #{name => <<"Deep Asset">>},

    CapturedPath = ets:new(captured_path, [public, set]),

    meck:expect(khepri, create, fun(_Store, Path, _Data) ->
        ets:insert(CapturedPath, {path, Path}),
        ok
    end),
    meck:expect(khepri, put, fun(_Store, _Path, _Data) -> ok end),

    macula_mri_khepri_store:register(test_store, MRI, Metadata),

    [{path, ResultPath}] = ets:lookup(CapturedPath, path),
    ?assertEqual([mri, asset, <<"io.macula">>, <<"org">>, <<"team">>, <<"project">>, <<"asset">>], ResultPath),

    ets:delete(CapturedPath).

%%====================================================================
%% Pagination Tests
%%====================================================================

list_children_with_limit() ->
    MRI = <<"mri:app:io.macula/acme">>,

    %% Return 10 children
    ChildData = maps:from_list([
        {[mri, app, <<"io.macula">>, <<"acme">>, integer_to_binary(I)],
         #{mri => <<"mri:app:io.macula/acme/", (integer_to_binary(I))/binary>>}}
        || I <- lists:seq(1, 10)
    ]),

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, ChildData} end),

    %% Request only 3 results
    Result = macula_mri_khepri_store:list_children_opts(test_store, MRI, #{limit => 3}),

    ?assertEqual(3, length(Result)).

list_children_with_offset() ->
    MRI = <<"mri:app:io.macula/acme">>,

    %% Return 10 children
    ChildData = maps:from_list([
        {[mri, app, <<"io.macula">>, <<"acme">>, integer_to_binary(I)],
         #{mri => <<"mri:app:io.macula/acme/", (integer_to_binary(I))/binary>>}}
        || I <- lists:seq(1, 10)
    ]),

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, ChildData} end),

    %% Request 3 results starting at offset 5
    Result = macula_mri_khepri_store:list_children_opts(test_store, MRI, #{limit => 3, offset => 5}),

    ?assertEqual(3, length(Result)).

list_descendants_with_pagination() ->
    MRI = <<"mri:app:io.macula">>,

    %% Return 20 descendants
    DescendantData = maps:from_list([
        {[mri, app, <<"io.macula">>, <<"item">>, integer_to_binary(I)],
         #{mri => <<"mri:app:io.macula/item/", (integer_to_binary(I))/binary>>}}
        || I <- lists:seq(1, 20)
    ]),

    meck:expect(khepri, get_many, fun(_Store, _Path) -> {ok, DescendantData} end),

    %% Request 5 results with offset 10
    Result = macula_mri_khepri_store:list_descendants_opts(test_store, MRI, #{limit => 5, offset => 10}),

    ?assertEqual(5, length(Result)).

list_by_type_with_pagination() ->
    Type = app,
    Realm = <<"io.macula">>,

    %% Return 15 indexed MRIs
    IndexData = maps:from_list([
        {<<"mri:app:io.macula/app", (integer_to_binary(I))/binary>>, true}
        || I <- lists:seq(1, 15)
    ]),

    meck:expect(khepri, get_many, fun(_Store, [mri_index, by_type | _]) ->
        {ok, IndexData}
    end),

    %% Request 4 results with offset 2
    Result = macula_mri_khepri_store:list_by_type_opts(test_store, Type, Realm, #{limit => 4, offset => 2}),

    ?assertEqual(4, length(Result)).
