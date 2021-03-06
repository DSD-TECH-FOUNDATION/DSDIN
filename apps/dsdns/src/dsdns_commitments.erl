
-module(dsdns_commitments).

-include("dsdns.hrl").

%% API
-export([id/1,
         new/3,
         serialize/1,
         deserialize/1]).

%% Getters
-export([expires/1,
         created/1,
         hash/1,
         owner/1]).

%%%===================================================================
%%% Types
%%%===================================================================
-opaque commitment() :: #commitment{}.

-type id() :: binary().
-type serialized() :: binary().

-export_type([id/0,
              commitment/0,
              serialized/0]).

-define(COMMITMENT_TYPE, name_commitment).
-define(COMMITMENT_VSN, 1).

%%%===================================================================
%%% API
%%%===================================================================

-spec id(commitment()) -> dsdns_hash:commitment_hash().
id(C) ->
    hash(C).

-spec new(dsdns_preclaim_tx:tx(), non_neg_integer(), dsdc_blocks:height()) -> commitment().
new(PreclaimTx, Expiration, BlockHeight) ->
    Expires = BlockHeight + Expiration,
    %% TODO: add assertions on fields, similarily to what is done in dsdo_oracles:new/2
    #commitment{hash    = dsdns_preclaim_tx:commitment(PreclaimTx),
                owner   = dsdns_preclaim_tx:account(PreclaimTx),
                created = BlockHeight,
                expires = Expires}.

-spec serialize(commitment()) -> binary().
serialize(#commitment{} = C) ->
    dsdc_object_serialization:serialize(
      ?COMMITMENT_TYPE,
      ?COMMITMENT_VSN,
      serialization_template(?COMMITMENT_VSN),
      [ {hash, hash(C)}
      , {owner, owner(C)}
      , {created, created(C)}
      , {expires, expires(C)}]).

-spec deserialize(binary()) -> commitment().
deserialize(Bin) ->
    [ {hash, Hash}
    , {owner, Owner}
    , {created, Created}
    , {expires, Expires}
    ] = dsdc_object_serialization:deserialize(
          ?COMMITMENT_TYPE,
          ?COMMITMENT_VSN,
          serialization_template(?COMMITMENT_VSN),
          Bin),
    #commitment{hash    = Hash,
                owner   = Owner,
                created = Created,
                expires = Expires}.

serialization_template(?COMMITMENT_VSN) ->
    [ {hash, binary}
    , {owner, binary}
    , {created, int}
    , {expires, int}
    ].

%%%===================================================================
%%% Getters
%%%===================================================================

-spec expires(commitment()) -> dsdc_blocks:height().
expires(C) -> C#commitment.expires.

-spec created(commitment()) -> dsdc_blocks:height().
created(C) -> C#commitment.created.

-spec hash(commitment()) -> dsdns_hash:commitment_hash().
hash(C) -> C#commitment.hash.

-spec owner(commitment()) -> dsdc_keys:pubkey().
owner(C) -> C#commitment.owner.
