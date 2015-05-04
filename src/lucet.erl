-module(lucet).

-export([connect/2]).

-define(JSON_FILE, "../lucet_design_fig14_A.json").
-define(PI1_ID, <<"Pi1">>).
-define(OFP1_ID, <<"PH1/VH1/OFS1/OFP1">>).
-define(PH1_VP1_ID, <<"PH1/VP1">>).
-define(PH1_PATCHP_ID, <<"PH1/PatchP">>).
-define(PH1_PATCHP_TO_OFP1_PATH,
        [?PH1_PATCHP_ID, <<"PH1/VP1.1">>, <<"PH1/VH1/VP1">>, ?OFP1_ID]).
-define(PI1_TO_PH1_PATCHP_PATH, [?PI1_ID, <<"PH1/PP1">>, ?PH1_PATCHP_ID]).

-define(TYPE(V), #{<<"type">> := #{value := V}}).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").

connect(Src, Dst) ->
    ok.

%% @doc Returns a path that starts in an endpoint, goes to an identifier
%% of `lm_pp' type and then following only 'bound_to' links reaches the
%% destination identifier. If such a path does not exists a path to the
%% last `lm_patchp' identifier will be returned. It may occur that
%% there's no `bound_to' link from the `lm_pp' identifier. Then a path
%% consisting of an `endpoint', `lm_pp' and `lm_patchp' will be returned.
-spec get_bound_path_from_endpoint(dby_identifier()) -> PathToDestination | PathToPatchp
                                              when
      PathToDestination :: [dby_identifier()],
      PathToPatchp :: {not_found, [dby_identifier()]}.

get_bound_path_from_endpoint(Destination) ->
    %% first identifier: an endpoint
    fun(_Id, ?TYPE(<<"endpoint">>), [], Acc) ->
            {continue, Acc};
       %% second identifier: physical port
       (_Id, ?TYPE(<<"lm_pp">>), [{_, ?TYPE(<<"endpoint">>), _ } |  _], Acc) ->
            {continue, Acc};
       %% finally we're following 'bound_to path' if such exists
       (Id, Md, [{_, _, ?TYPE(<<"bound_to">>)}] = Path, Acc)
          when Id =:= Destination ->
            {stop, lists:reverse(Path, [{Id, Md, #{}}])};
       (Id, Md, [{_, _, ?TYPE(<<"bound_to">>)}] = Path, Acc) ->
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
-spec get_bound_path_from_patchp(dby_identifier()) ->
                                        [dby_identifier()] | not_found.

get_bound_path_from_patchp(Destination) ->
    %% we expect to start in patchp identifier
    fun(_Id, ?TYPE(<<"lm_patchp">>), [], Acc) ->
            {continue, Acc};
       %% then we expect a virtual port that is 'part_of' the patchp
       (_Id, ?TYPE(<<"lm_vp">>), [{_, _, ?TYPE(<<"part_of">>)}], Acc) ->
            {continue, Acc};
       %% finally we expect to find the 'bound to path' to the destination
       (Id, Md, [{_, _, ?TYPE(<<"bound_to">>)} | _] = Path, Acc)
          when Id =:= Destination ->
            {stop, lists:reverse(Path, [{Destination, Md, #{}}])};
       (_Id, _Md, [{_, _, ?TYPE(<<"bound_to">>)} | _] = Path, Acc) ->
            {continue, Acc};
       %% any other path is not interesting for us
       (_, _, _, Acc) ->
            {skip, Acc}
    end.

%% Tests

ld_fig14a_test_() ->
    {foreach, fun setup_dobby/0, fun(_) -> ok end,
     [{"Not connected path",
       fun it_returns_last_patchp_of_unbound_path/0},
      {"Shortest path from patchp",
       fun it_returns_shortest_path_from_patchp_to_dst/0}]}.

setup_dobby() ->
    application:stop(dobby),
    {ok, _} = application:ensure_all_started(dobby),
    ok = dby_bulk:import(json, ?JSON_FILE).

it_returns_last_patchp_of_unbound_path() ->
    {not_found, Path} = dby:search(get_bound_path_from_endpoint(?OFP1_ID),
                                   [],
                                   ?PI1_ID,
                                   [breadth, {max_depth, 100}]),
    ExpectedPath = ?PI1_TO_PH1_PATCHP_PATH,
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).

it_returns_shortest_path_from_patchp_to_dst() ->
    Path = dby:search(get_bound_path_from_patchp(?OFP1_ID),
                      not_found,
                      ?PH1_PATCHP_ID,
                      [breadth, {max_depth, 100}]),
    ExpectedPath = ?PH1_PATCHP_TO_OFP1_PATH,
    ?assertEqual(ExpectedPath, lists:map(fun({ActualId, _, _}) ->
                                                 ActualId
                                         end, Path)).
