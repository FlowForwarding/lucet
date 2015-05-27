-module(lucet).

-export([wire/2,
	 generate_domain_config/2]).

-define(JSON_FILE, "../lucet_design_fig14_A.json").
-define(PI1_ID, <<"Pi1">>).
-define(OFP1_ID, <<"PH1/VH1/OFS1/OFP1">>).
-define(PH1_PP1_ID, <<"PH1/PP1">>).
-define(PH1_VP1_ID, <<"PH1/VP1">>).
-define(PH1_VP11_ID, <<"PH1/VP1.1">>).
-define(PH1_PATCHP_ID, <<"PH1/PatchP">>).
-define(PH1_PATCHP_TO_OFP1_PATH,
        [?PH1_PATCHP_ID, <<"PH1/VP1.1">>, <<"PH1/VH1/VP1">>, ?OFP1_ID]).
-define(PI1_TO_PH1_PATCHP_PATH, [?PI1_ID, <<"PH1/PP1">>, ?PH1_PATCHP_ID]).

-define(TYPE(V), #{<<"type">> := #{value := V}}).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").

%% API

wire(Endpoint, OFPort) ->
    connect_endpoint_with_of_port(Endpoint, OFPort),
    generate_domain_config_and_run_vm().

generate_domain_config(PhysicalHost, MgmtIfMac) ->
    %% TODO: use domain config template file
    PatchPanel = PhysicalHost ++ "/PatchP",
    case dby:search(
	   fun(_, #{<<"wires">> := #{value := Wires}}, _, _) ->
		   {stop, {found, Wires}}
	   end,
	   not_found,
	   list_to_binary(PatchPanel),
	   [{max_depth, 1}]) of
	{found, Wires} ->
	    FirstVif = {MgmtIfMac, "xenbr0"},
	    MgmtIfMacNo = mac_string_to_number(MgmtIfMac),
	    OtherVifs =
		maps:fold(
		  fun(_Port1, <<"null">>, Acc) ->
			  Acc;
		     (Port1, Port2, Acc) ->
			  case re:run(Port1, "^" ++ PhysicalHost ++ "/PP([0-9]+)$", [{capture, all_but_first, list}]) of
			      {match, [IfNo]} ->
				  MacNo = MgmtIfMacNo + list_to_integer(IfNo),
				  [{mac_number_to_string(MacNo), "xenbr" ++ IfNo}] ++ Acc;
			      nomatch ->
				  %% Not starting from a physical port
				  Acc
			  end
		  end, [], Wires),
	    VifList = [FirstVif] ++ lists:sort(OtherVifs),
	    VifString = "vif = [" ++
		string:join(["'mac=" ++ Mac ++ ",bridge=" ++ If ++ "'" || {Mac, If} <- VifList],
			    ",\n       ") ++
		"]\n",
	    io:format("~s~n", [VifString]),
	    ok;
	not_found ->
	    io:format(standard_error, "Patch panel ~s not found in dobby!~n", [PatchPanel]),
	    {error, {not_found, PatchPanel}}
    end.

%% Internal functions

mac_string_to_number(MacS) ->
    HexBytes = string:tokens(MacS, ":"),
    lists:foldl(fun(HexByte, Acc) ->
			list_to_integer(HexByte, 16) bor (Acc bsl 8)
		end, 0, HexBytes).

mac_number_to_string(Mac) ->
    <<One:8, Two:8, Three:8, Four:8, Five:8, Six:8>> = <<Mac:48>>,
    string:join(
      lists:map(fun(Byte) ->
			lists:flatten(io_lib:format("~2.16.0b", [Byte]))
		end, [One, Two, Three, Four, Five, Six]),
      ":").

generate_domain_config_and_run_vm() ->
    %% TODO
    ok.

%% @doc Connects an `Endpoint' with the `OFPort'.
%%
%% It assumes that the `Endpoint' is connected to a physical port (PP).
%% Then it connects identifiers in the Dobby so that there's a path between
%% the physical port and the `OFPort' consisting only of 'bound_to' links.
%% It also marks the connection on the appropriate PatchP identifier.
-spec connect_endpoint_with_of_port(dby_identifier(), dby_identifier()) ->
                                           ok | {error, Reason :: term()}.

connect_endpoint_with_of_port(Endpoint, OFPort) ->
    case search_bound_path_from_endpoint_to_of_port(Endpoint, OFPort) of
        {not_found, ToPatchp0} ->
            ToPatchp = filter_out_md(ToPatchp0),
            Patchp = lists:last(ToPatchp),
            FromPatchp0 = search_path_from_patchp_to_of_port(Patchp, OFPort),
            assert_from_patchp_path_exists(FromPatchp0),
            FromPatchp = filter_out_md(FromPatchp0),
            {PortA, PortB} =
                ports_to_be_connected(ToPatchp ++ tl(FromPatchp), Patchp),
            bound_ports_on_patch_panel(Patchp, PortA, PortB),
	    %% Now that the physical port that Endpoint is connected
	    %% to and the virtual port that OFPort is connected to
	    %% have a link, we can publish a link between Endpoint and
	    %% OFPort, so that Weave can get its job done.
	    ok = dby:publish(<<"lucet">>, Endpoint, OFPort,
			     [{<<"type">>, <<"connected_to">>}],
			     [persistent]);
        _ExistingPath ->
            ok
    end.

assert_from_patchp_path_exists(not_found) ->
    throw(not_found);
assert_from_patchp_path_exists(_) ->
    ok.

filter_out_md(Path) ->
    lists:map(fun({Id, _Md, _LinkMd}) -> Id end, Path).

ports_to_be_connected([PortA, PatchP, PortB | _], PatchP) ->
    {PortA, PortB};
ports_to_be_connected([_ | T], PatchP) ->
    ports_to_be_connected(T, PatchP);
ports_to_be_connected([], _) ->
    throw(not_found).


%% @doc Returns a path that starts in an endpoint, goes to an identifier
%% of `lm_pp' type and then following only 'bound_to' links reaches the
%% destination identifier. If such a path does not exists a path to the
%% last `lm_patchp' identifier will be returned. It may occur that
%% there's no `bound_to' link from the `lm_pp' identifier. Then a path
%% consisting of an `endpoint', `lm_pp' and `lm_patchp' will be returned.
-spec get_bound_path_from_endpoint_fun(dby_identifier()) -> PathToDestination | PathToPatchp
                                              when
      PathToDestination :: [dby_identifier()],
      PathToPatchp :: {not_found, [dby_identifier()]}.

get_bound_path_from_endpoint_fun(Destination) ->
    %% first identifier: an endpoint
    fun(_Id, ?TYPE(<<"endpoint">>), [], Acc) ->
            {continue, Acc};
       %% second identifier: physical port
       (_Id, ?TYPE(<<"lm_pp">>), [{_, ?TYPE(<<"endpoint">>), _ } |  _], Acc) ->
            {continue, Acc};
       %% finally we're following 'bound_to path' if such exists
       (Id, Md, [{_, _, ?TYPE(<<"bound_to">>)} | _] = Path, _)
          when Id =:= Destination ->
            {stop, lists:reverse(Path, [{Id, Md, #{}}])};
       (_Id, _Md, [{_, _, ?TYPE(<<"bound_to">>)} | _], Acc) ->
            {continue, Acc};
       %% store the most recent patch panel in case there's no 'bound_to' path
       (Id, ?TYPE(<<"lm_patchp">>) = Md, Path, _Acc) ->
            PathToPatchP = lists:reverse(Path, [{Id, Md, #{}}]),
            {skip, {not_found, PathToPatchP}};
       %% any other path is not interesting for us
       (_, _, _, Acc) ->
            {skip, Acc}
    end.

%% @doc Returns a path that starts in a `lm_patchp', goes to an
%% identifier of `lm_vp' type and then reaches `Destination' identifier
%% through the links with the `bound_to' type.
-spec get_bound_path_from_patchp_fun(dby_identifier()) ->
                                        [dby_identifier()] | not_found.

get_bound_path_from_patchp_fun(Destination) ->
    %% we expect to start in patchp identifier
    fun(_Id, ?TYPE(<<"lm_patchp">>), [], Acc) ->
            {continue, Acc};
       %% then we expect a virtual port that is 'part_of' the patchp
       (_Id, ?TYPE(<<"lm_vp">>), [{_, _, ?TYPE(<<"part_of">>)}], Acc) ->
            {continue, Acc};
       %% finally we expect to find the 'bound to path' to the destination
       (Id, Md, [{_, _, ?TYPE(<<"bound_to">>)} | _] = Path, _Acc)
          when Id =:= Destination ->
            {stop, lists:reverse(Path, [{Destination, Md, #{}}])};
       (_Id, _Md, [{_, _, ?TYPE(<<"bound_to">>)} | _], Acc) ->
            {continue, Acc};
       %% any other path is not interesting for us
       (_, _, _, Acc) ->
            {skip, Acc}
    end.


%% @doc Bounds `PortA' with `PortB' that exists on `PatchPId'.
%%
%% It creates a bound_to link from `PortA' to `PortB' and updates
%% wires metadata on the `PathchpId' indicating that the `PortA' and `PortB'
%% are connected.
bound_ports_on_patch_panel(PatchpId, PortA, PortB) ->
    ok = dby:publish(<<"lucet">>, PortA, PortB, [{<<"type">>, <<"bound_to">>}],
                     [persistent]),
    MdFun = fun(MdProplist) ->
                    Wires0 = proplists:get_value(<<"wires">>, MdProplist),
                    Wires1 = maps:update(PortA, PortB, Wires0),
                    Wires2 = maps:update(PortB, PortA, Wires1),
                    [{<<"wires">>, Wires2} | proplists:delete(<<"wires">>,
                                                              MdProplist)]
            end,
    ok = dby:publish(<<"lucet">>, {PatchpId, MdFun}, [persistent]).

search_bound_path_from_endpoint_to_of_port(Endpoint, OFPort) ->
    dby:search(get_bound_path_from_endpoint_fun(OFPort),
               [],
               Endpoint,
               [breadth, {max_depth, 100}]).

search_path_from_patchp_to_of_port(PatchP, OFPort) ->
    dby:search(get_bound_path_from_patchp_fun(OFPort),
               not_found,
               PatchP,
               [breadth, {max_depth, 100}]).

%% Tests

ld_fig14a_test_() ->
    {foreach, fun setup_dobby/0, fun(_) -> ok end,
     [{"Not connected path",
       fun it_returns_last_patchp_of_unbound_path/0},
      {"Shortest path from patchp",
       fun it_returns_shortest_path_from_patchp_to_dst/0},
      {"Connecting on patchp",
       fun it_bounds_ports_on_patchp/0},
      {"Connecting an Endpoint with OF Port",
       fun it_connects_endpoint_with_of_port/0},
      {"Connecting an Endpoint with OF Port (already exists)",
       fun it_does_nothing_when_endpoint_already_connected_to_endpoint/0}]}.

setup_dobby() ->
    application:stop(dobby),
    {ok, _} = application:ensure_all_started(dobby),
    ok = dby_mnesia:clear(),
    ok = dby_bulk:import(json, ?JSON_FILE).

it_returns_last_patchp_of_unbound_path() ->
    {not_found, Path} = dby:search(get_bound_path_from_endpoint_fun(?OFP1_ID),
                                   [],
                                   ?PI1_ID,
                                   [breadth, {max_depth, 100}]),
    ExpectedPath = ?PI1_TO_PH1_PATCHP_PATH,
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).

it_returns_shortest_path_from_patchp_to_dst() ->
    Path = dby:search(get_bound_path_from_patchp_fun(?OFP1_ID),
                      not_found,
                      ?PH1_PATCHP_ID,
                      [breadth, {max_depth, 100}]),
    ExpectedPath = ?PH1_PATCHP_TO_OFP1_PATH,
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).
it_bounds_ports_on_patchp() ->
    %% GIVEN
    PatchpId = ?PH1_PATCHP_ID,
    PortA = ?PH1_PP1_ID,
    PortB = ?PH1_VP11_ID,

    %% WHEN
    bound_ports_on_patch_panel(PatchpId, PortA, PortB),

    %% THEN
    %% Maybe we should only check that there's a bound_to link PortaA-PortB
    Path = dby:search(get_bound_path_from_endpoint_fun(?OFP1_ID),
                      [],
                      ?PI1_ID,
                      [breadth, {max_depth, 100}]),
    ExpectedPath = lists:filter(fun(?PH1_PATCHP_ID) ->
                                        false;
                                   (_) ->
                                        true
                                end, ?PI1_TO_PH1_PATCHP_PATH
                                ++ ?PH1_PATCHP_TO_OFP1_PATH),
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).

it_connects_endpoint_with_of_port() ->
    %% GIVEN
    Endpoint = ?PI1_ID,
    OFPort = ?OFP1_ID,

    %% WHEN
    ok = connect_endpoint_with_of_port(Endpoint, OFPort),

    %% THEN
    assert_endpoint_connected_to_of_port(Endpoint, OFPort).

it_does_nothing_when_endpoint_already_connected_to_endpoint() ->
    %% GIVEN
    Endpoint = ?PI1_ID,
    OFPort = ?OFP1_ID,
    ok = connect_endpoint_with_of_port(Endpoint, OFPort),
    Path = search_bound_path_from_endpoint_to_of_port(Endpoint, OFPort),

    %% WHEN
    ok = connect_endpoint_with_of_port(Endpoint, OFPort),

    %% THEN
    ?assertEqual(Path,
                 search_bound_path_from_endpoint_to_of_port(Endpoint, OFPort)).

%% Tests helper functions

assert_endpoint_connected_to_of_port(Endpoint, OFPort) ->
    Path = dby:search(get_bound_path_from_endpoint_fun(OFPort),
                  [],
                      Endpoint,
                  [breadth, {max_depth, 100}]),
    ExpectedPath = pi1_to_ofp1_path(),
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).

pi1_to_ofp1_path() ->
    lists:filter(fun(?PH1_PATCHP_ID) ->
                         false;
                    (_) ->
                         true
                 end, ?PI1_TO_PH1_PATCHP_PATH ++ ?PH1_PATCHP_TO_OFP1_PATH).

