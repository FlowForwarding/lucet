-module(lucet_utils).

-include("lucet_logger.hrl").

-export([connect_to_dobby/0]).

-define(DEFAULT_DOBBY_NODE, 'dobby@127.0.0.1').

%%%===================================================================
%%% API
%%%===================================================================

connect_to_dobby() ->
    DobbyNode = application:get_env(lucet, dobby_node, ?DEFAULT_DOBBY_NODE),
    case net_adm:ping(DobbyNode) of
        pong ->
            ?INFO("Connected to dobby node: ~p", [DobbyNode]);
        pang ->
            ?ERROR("Failed to connect to dobby node: ~p", [DobbyNode]),
            throw({connecting_to_dobby_failed, DobbyNode})
    end.


