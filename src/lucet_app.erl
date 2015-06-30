-module(lucet_app).

-behaviour(application).

-include("lucet_logger.hrl").

%% Application callbacks
-export([start/2, stop/1]).

-define(DEFAULT_DOBBY_NODE, 'dobby@127.0.0.1').
-define(DEFAULT_SSH_PORT, 22333).
-define(SSH_SYSTEM_DIR, "system_dir").
-define(SSH_USER_DIR, "user_dir").

%%%===================================================================
%%% Application callbacks
%%%===================================================================

start(_StartType, _StartArgs) ->
    try
        connect_to_dobby(),
        start_ssh_daemon(),
        start_lucet_sup()
    catch
        throw:Error ->
            {error, Error}
    end.

stop(_State) ->
    ok.

%%%===================================================================
%%% Internal functions
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

start_ssh_daemon() ->
    Port = application:get_env(lucet, ssh_port, ?DEFAULT_SSH_PORT),
    PrivDir = code:priv_dir(lucet),
    case ssh:daemon(Port,
                    [{system_dir, filename:join([PrivDir, ?SSH_SYSTEM_DIR])},
                     {user_dir, filename:join(PrivDir, ?SSH_USER_DIR)}]) of
        {ok, _Ref} ->
            ?INFO("Started ssh daemon on port ~p", [Port]);
        {error, Error} ->
            ?ERROR("Failed to start ssh daemon on port ~p", [Port]),
            throw({failed_to_start_ssh_daemon, Port, Error})
    end.

start_lucet_sup() ->
    case lucet_sup:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.


