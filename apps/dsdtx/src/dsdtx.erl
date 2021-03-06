%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, Dasudian Technologies
%%%-------------------------------------------------------------------

-module(dsdtx).

-export([ accounts/1
        , check/4
        , check_from_contract/4
        , deserialize_from_binary/1
        , fee/1
        , is_tx_type/1
        , new/2
        , nonce/1
        , origin/1
        , process/4
        , process_from_contract/4
        , serialize_for_client/1
        , serialize_to_binary/1
        , signers/2
        , specialize_type/1
        , specialize_callback/1
        , update_tx/2
        , tx_type/1
        , tx_types/0]).

-ifdef(TEST).
-export([tx/1]).
-endif.

%% -- Types ------------------------------------------------------------------
-record(dsdtx, { type :: tx_type()
              , cb   :: module()
              , tx   :: tx_instance() }).

-opaque tx() :: #dsdtx{}.

-type tx_type() :: spend_tx
                 | oracle_register_tx
                 | oracle_extend_tx
                 | oracle_query_tx
                 | oracle_response_tx
                 | name_preclaim_tx
                 | name_claim_tx
                 | name_transfer_tx
                 | name_update_tx
                 | name_revoke_tx
                 | contract_create_tx
                 | contract_call_tx
                 | channel_create_tx
                 | channel_deposit_tx
                 | channel_withdraw_tx
                 | channel_close_mutual_tx
                 | channel_close_solo_tx
                 | channel_slash_tx
                 | channel_settle_tx
                 | channel_offchain_tx.

-type tx_instance() :: dsdc_spend_tx:tx()
                     | dsdo_register_tx:tx()
                     | dsdo_extend_tx:tx()
                     | dsdo_query_tx:tx()
                     | dsdo_response_tx:tx()
                     | dsdns_preclaim_tx:tx()
                     | dsdns_claim_tx:tx()
                     | dsdns_transfer_tx:tx()
                     | dsdns_update_tx:tx()
                     | dsdns_revoke_tx:tx()
                     | dsdct_create_tx:tx()
                     | dsdct_call_tx:tx()
                     | dsdsc_create_tx:tx()
                     | dsdsc_deposit_tx:tx()
                     | dsdsc_withdraw_tx:tx()
                     | dsdsc_close_mutual_tx:tx()
                     | dsdsc_close_solo_tx:tx()
                     | dsdsc_slash_tx:tx()
                     | dsdsc_settle_tx:tx()
                     | dsdsc_offchain_tx:tx().

%% @doc Where does this transaction come from? Is it a top level transaction or was it created by
%%      smart contract. In the latter case the fee logic is different.
-type tx_context() :: dsdtx_transaction | dsdtx_contract.

-export_type([ tx/0
             , tx_instance/0
             , tx_type/0
             , tx_context/0 ]).

%% -- Behaviour definition ---------------------------------------------------

-callback new(Args :: map()) ->
    {ok, Tx :: tx()} | {error, Reason :: term()}.

-callback type() -> atom().

-callback fee(Tx :: tx_instance()) ->
    Fee :: integer().

-callback ttl(Tx :: tx_instance()) ->
    TTL :: dsdc_blocks:height().

-callback nonce(Tx :: tx_instance()) ->
    Nonce :: non_neg_integer().

-callback origin(Tx :: tx_instance()) ->
    Origin :: dsdc_keys:pubkey() | undefined.

-callback accounts(Tx :: tx_instance()) ->
    [dsdc_keys:pubkey()].

-callback signers(Tx :: tx_instance(), Trees :: dsdc_trees:trees()) ->
    {ok, [dsdc_keys:pubkey()]} | {error, atom()}.

-callback check(Tx :: tx_instance(), Context :: tx_context(),
                Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
                ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()} | {error, Reason :: term()}.

-callback process(Tx :: tx_instance(), Context :: tx_context(),
                  Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
                  ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()}.

-callback serialize(Tx :: tx_instance()) ->
    term().

-callback serialization_template(Vsn :: non_neg_integer()) ->
    term().

-callback deserialize(Vsn :: integer(), SerializedTx :: term()) ->
    Tx :: tx_instance().

-callback for_client(Tx :: tx_instance()) ->
    map().

%% -- ADT Implementation -----------------------------------------------------

-spec new(CallbackModule :: module(),  Tx :: tx_instance()) ->
    Tx :: tx().
new(Callback, Tx) ->
    Type = Callback:type(),
    #dsdtx{ type = Type, cb = Callback, tx = Tx }.

-spec tx_type(TxOrTxType :: tx_type() | tx()) -> binary().
tx_type(#dsdtx{ type = TxType }) ->
    tx_type(TxType);
tx_type(TxType) when is_atom(TxType) ->
    erlang:atom_to_binary(TxType, utf8).

-spec fee(Tx :: tx()) -> Fee :: integer().
fee(#dsdtx{ cb = CB, tx = Tx }) ->
    CB:fee(Tx).

-spec nonce(Tx :: tx()) -> Nonce :: non_neg_integer() | undefined.
nonce(#dsdtx{ cb = CB, tx = Tx }) ->
    CB:nonce(Tx).

-spec origin(Tx :: tx()) -> Origin :: dsdc_keys:pubkey() | undefined.
origin(#dsdtx{ cb = CB, tx = Tx }) ->
    CB:origin(Tx).

-spec accounts(Tx :: tx()) -> [dsdc_keys:pubkey()].
accounts(#dsdtx{ cb = CB, tx = Tx }) ->
    CB:accounts(Tx).

-spec signers(Tx :: tx(), Trees :: dsdc_trees:trees()) ->
    {ok, [dsdc_keys:pubkey()]} | {error, atom()}.
signers(#dsdtx{ cb = CB, tx = Tx }, Trees) ->
    CB:signers(Tx, Trees).

-spec check(Tx :: tx(), Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
            ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()} | {error, Reason :: term()}.
check(#dsdtx{ cb = CB, tx = Tx }, Trees, Height, ConsensusVersion) ->
    case {CB:fee(Tx) >= dsdc_governance:minimum_tx_fee(), CB:ttl(Tx) >= Height} of
        {true, true} ->
            CB:check(Tx, dsdtx_transaction, Trees, Height, ConsensusVersion);
        {false, _} ->
            {error, too_low_fee};
        {_, false} ->
            {error, ttl_expired}
    end.

-spec check_from_contract(Tx :: tx(), Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
                          ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()} | {error, Reason :: term()}.
check_from_contract(#dsdtx{ cb = CB, tx = Tx }, Trees, Height, ConsensusVersion) ->
    CB:check(Tx, dsdtx_contract, Trees, Height, ConsensusVersion).

-spec process(Tx :: tx(), Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
              ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()}.
process(#dsdtx{ cb = CB, tx = Tx }, Trees, Height, ConsensusVersion) ->
    CB:process(Tx, dsdtx_transaction, Trees, Height, ConsensusVersion).

-spec process_from_contract(Tx :: tx(), Trees :: dsdc_trees:trees(), Height :: non_neg_integer(),
                            ConsensusVersion :: non_neg_integer()) ->
    {ok, NewTrees :: dsdc_trees:trees()}.

process_from_contract(#dsdtx{ cb = CB, tx = Tx }, Trees, Height, ConsensusVersion) ->
    CB:process(Tx, dsdtx_contract, Trees, Height, ConsensusVersion).

-spec serialize_for_client(Tx :: tx()) -> map().
serialize_for_client(#dsdtx{ cb = CB, type = Type, tx = Tx }) ->
    Res = CB:for_client(Tx),
    Res#{ <<"type">> => tx_type(Type) }.

-spec serialize_to_binary(Tx :: tx()) -> term().
serialize_to_binary(#dsdtx{ cb = CB, type = Type, tx = Tx }) ->
    {Vsn, Fields} = CB:serialize(Tx),
    dsdc_object_serialization:serialize(
      Type,
      Vsn,
      CB:serialization_template(Vsn),
      Fields).

-spec deserialize_from_binary(Bin :: binary()) -> Tx :: tx().
deserialize_from_binary(Bin) ->
    {Type, Vsn, RawFields} =
        dsdc_object_serialization:deserialize_type_and_vsn(Bin),
    CB = type_to_cb(Type),
    Template = CB:serialization_template(Vsn),
    Fields = dsdc_serialization:decode_fields(Template, RawFields),
    #dsdtx{cb = CB, type = Type, tx = CB:deserialize(Vsn, Fields)}.

type_to_cb(spend_tx)                -> dsdc_spend_tx;
type_to_cb(oracle_register_tx)      -> dsdo_register_tx;
type_to_cb(oracle_extend_tx)        -> dsdo_extend_tx;
type_to_cb(oracle_query_tx)         -> dsdo_query_tx;
type_to_cb(oracle_response_tx)      -> dsdo_response_tx;
type_to_cb(name_preclaim_tx)        -> dsdns_preclaim_tx;
type_to_cb(name_claim_tx)           -> dsdns_claim_tx;
type_to_cb(name_transfer_tx)        -> dsdns_transfer_tx;
type_to_cb(name_update_tx)          -> dsdns_update_tx;
type_to_cb(name_revoke_tx)          -> dsdns_revoke_tx;
type_to_cb(name_create_tx)          -> dsdns_create_tx;
type_to_cb(contract_call_tx)        -> dsdct_call_tx;
type_to_cb(contract_create_tx)      -> dsdct_create_tx;
type_to_cb(channel_create_tx)       -> dsdsc_create_tx;
type_to_cb(channel_deposit_tx)      -> dsdsc_deposit_tx;
type_to_cb(channel_withdraw_tx)     -> dsdsc_withdraw_tx;
type_to_cb(channel_close_solo_tx)   -> dsdsc_close_solo_tx;
type_to_cb(channel_close_mutual_tx) -> dsdsc_close_mutual_tx;
type_to_cb(channel_slash_tx)        -> dsdsc_slash_tx;
type_to_cb(channel_settle_tx)       -> dsdsc_settle_tx;
type_to_cb(channel_offchain_tx)     -> dsdsc_offchain_tx.

-spec specialize_type(Tx :: tx()) -> {tx_type(), tx_instance()}.
specialize_type(#dsdtx{ type = Type, tx = Tx }) -> {Type, Tx}.

-spec specialize_callback(Tx :: tx()) -> {module(), tx_instance()}.
specialize_callback(#dsdtx{ cb = CB, tx = Tx }) -> {CB, Tx}.

-spec update_tx(tx(), tx_instance()) -> tx().
update_tx(#dsdtx{} = Tx, NewTxI) ->
    Tx#dsdtx{tx = NewTxI}.

-spec tx_types() -> list(tx_type()).
tx_types() ->
    [ spend_tx
    , oracle_register_tx
    , oracle_extend_tx
    , oracle_query_tx
    , oracle_response_tx
    , name_preclaim_tx
    , name_claim_tx
    , name_transfer_tx
    , name_update_tx
    , name_revoke_tx
    , name_create_tx
    , contract_call_tx
    , contract_create_tx
    , channel_create_tx
    , channel_deposit_tx
    , channel_withdraw_tx
    , channel_close_mutual_tx
    , channel_close_solo_tx
    , channel_slash_tx
    , channel_settle_tx
    , channel_offchain_tx
    ].

-spec is_tx_type(MaybeTxType :: binary() | atom()) -> boolean().
is_tx_type(X) when is_binary(X) ->
    try
        is_tx_type(erlang:binary_to_existing_atom(X, utf8))
    catch _:_ ->
            false
    end;
is_tx_type(X) when is_atom(X) ->
    lists:member(X, tx_types()).

-ifdef(TEST).
tx(Tx) ->
    Tx#dsdtx.tx.
-endif.

