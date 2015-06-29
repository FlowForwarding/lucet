-module(lucet_app).

-behaviour(application).

-include("lucet_logger.hrl").

%% Application callbacks
-export([start/2, stop/1]).

-define(DEFAULT_DOBBY_NODE, 'dobby@127.0.0.1').

%%%===================================================================
%%% Application callbacks
%%%===================================================================

start(_StartType, _StartArgs) ->
    case connect_to_dobby() of
        ok ->
            start_lucet_sup();
        {error, _} = Error ->
            Error
    end.

stop(_State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

connect_to_dobby() ->
    DobbyNode = application:get_env(lucet, dobby_node, ?DEFAULT_DOBBY_NODE),
    case net_adm:ping(DobbyNode) of
        pang ->
            ?ERROR("Cannot connect to dobby node: ~p", [DobbyNode]),
            {error, {cannot_connect_to_dobby, DobbyNode}};
        pong ->
            ?INFO("Connected to dobby node: ~p", [DobbyNode]),
            ok
    end.

start_lucet_sup() ->
    case lucet_sup:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.


