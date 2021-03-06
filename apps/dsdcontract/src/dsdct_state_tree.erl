
-module(dsdct_state_tree).

%% API
-export([ commit_to_db/1
        , empty/0
        , empty_with_backend/0
        , get_contract/2
        , insert_contract/2
        , enter_contract/2
        , lookup_contract/2
        , root_hash/1]).

-export_type([tree/0]).

%%%===================================================================
%%% Types
%%%===================================================================

-type contract_tree() :: dsdu_mtrees:mtree().

-record(contract_tree, {
          contracts = dsdu_mtrees:empty() :: contract_tree()
    }).

-opaque tree() :: #contract_tree{}.

%%%===================================================================
%%% API
%%%===================================================================

-spec empty() -> tree().
empty() ->
    #contract_tree{}.

-spec empty_with_backend() -> tree().
empty_with_backend() ->
    CtTree = dsdu_mtrees:empty_with_backend(dsdc_db_backends:contracts_backend()),
    #contract_tree{contracts = CtTree}.

%% -- Contracts --

-spec insert_contract(dsdct_contracts:contract(), tree()) -> tree().
insert_contract(Contract, Tree = #contract_tree{ contracts = CtTree }) ->
    Id         = dsdct_contracts:id(Contract),
    Serialized = dsdct_contracts:serialize(Contract),
    CtTree1    = dsdu_mtrees:insert(Id, Serialized, CtTree),
    CtTree2    = insert_store(Contract, CtTree1),
    Tree#contract_tree{ contracts = CtTree2 }.

insert_store(Contract, CtTree) ->
    Id = dsdct_contracts:store_id(Contract),
    Store = dsdct_contracts:state(Contract),
    insert_store_nodes(Id, Store, CtTree).

insert_store_nodes(Prefix, Store, CtTree) ->
    Insert = fun (Key, Value, Tree) ->
                     Id = <<Prefix/binary, Key/binary>>,
                     dsdu_mtrees:insert(Id, Value, Tree)
             end,
     maps:fold(Insert, CtTree, Store).


%% @doc Update an existing contract.
-spec enter_contract(dsdct_contracts:contract(), tree()) -> tree().
enter_contract(Contract, Tree = #contract_tree{ contracts = CtTree }) ->
    Id         = dsdct_contracts:id(Contract),
    Serialized = dsdct_contracts:serialize(Contract),
    CtTree1    = dsdu_mtrees:enter(Id, Serialized, CtTree),
    OldContract = get_contract(Id, Tree),
    OldStore = dsdct_contracts:state(OldContract),
    CtTree2    = enter_store(Contract, OldStore, CtTree1),
    Tree#contract_tree{ contracts = CtTree2 }.

enter_store(Contract, OldStore, CtTree) ->
    Id = dsdct_contracts:store_id(Contract),
    Store = dsdct_contracts:state(Contract),
    MergedStore = maps:merge(Store, OldStore),
    %% Merged store contains all keys, and old Values.
    enter_store_nodes(Id, MergedStore, Store, OldStore, CtTree).

enter_store_nodes(Prefix, MergedStore, Store, OldStore, CtTree) ->
    %% Iterate over all (merged) keys.
    Insert = fun (Key,_MergedVal, Tree) ->
                     Id = <<Prefix/binary, Key/binary>>,
                     %% Check if key exist in new store
                     %% If not overwrite with empty tree.
                     case {maps:get(Key,    Store, <<>>),
                           maps:get(Key, OldStore, <<>>)} of
                         {Same, Same} -> Tree;
                         {Value,   _}    -> dsdu_mtrees:enter(Id, Value, Tree)
                     end
             end,
     maps:fold(Insert, CtTree, MergedStore).

-spec get_contract(dsdct_contracts:id(), tree()) -> dsdct_contracts:contract().
get_contract(Id, #contract_tree{ contracts = CtTree }) ->
    Contract = dsdct_contracts:deserialize(Id, dsdu_mtrees:get(Id, CtTree)),
    add_store(Contract, CtTree).

add_store(Contract, CtTree) ->
    Id = dsdct_contracts:store_id(Contract),
    Iterator = dsdu_mtrees:iterator_from(Id, CtTree),
    Next = dsdu_mtrees:iterator_next(Iterator),
    Size = byte_size(Id),
    Store = find_store_keys(Id, Next, Size, #{}),
    dsdct_contracts:set_state(Store, Contract).

find_store_keys(_, '$end_of_table', _, Store) ->
    Store;
find_store_keys(Id, {PrefixedKey, Val, Iter}, PrefixSize, Store) ->
    case PrefixedKey of
        <<Id:PrefixSize/binary, Key/binary>> ->
            Store1 = Store#{ Key => Val},
            Next = dsdu_mtrees:iterator_next(Iter),
            find_store_keys(Id, Next, PrefixSize, Store1);
        _ ->
            Store
    end.


-spec lookup_contract(dsdct_contracts:id(), tree()) -> {value, dsdct_contracts:contract()} | none.
lookup_contract(Id, Tree) ->
    CtTree = Tree#contract_tree.contracts,
    case dsdu_mtrees:lookup(Id, CtTree) of
        {value, Val} -> {value, add_store(dsdct_contracts:deserialize(Id, Val), CtTree)};
        none         -> none
    end.

%% -- Hashing --

-spec root_hash(tree()) -> {ok, dsdu_mtrees:root_hash()} | {error, empty}.
root_hash(#contract_tree{contracts = CtTree}) ->
    dsdu_mtrees:root_hash(CtTree).

%% -- Commit to db --

-spec commit_to_db(tree()) -> tree().
commit_to_db(#contract_tree{contracts = CtTree} = Tree) ->
    Tree#contract_tree{contracts = dsdu_mtrees:commit_to_db(CtTree)}.
