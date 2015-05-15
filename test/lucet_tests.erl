-module(lucet_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").

%% Topo generated ussing the following command:
%% ./utils/appfest_gen -out lucet_design_fig_17_A.json -physical_ports 1 \
%% -ofp_ports 2 -virtual_hosts 1 -physical_hosts 2
-define(JSON_FILE, "../lucet_design_fig_17_A.json").

-define(EP1, <<"PH1/VH2/EP1">>).
-define(OFS1_OFP2, <<"PH1/VH1/OFS1/OFP2">>).
-define(EP1_TO_OFS1_OFP2_PATH,
        [?EP1, <<"PH1/VH2/VP0">>, <<"PH1/VP2.1">>, <<"PH1/PatchP">>,
         <<"PH1/VP1.2">>, <<"PH1/VH1/VP2">>, ?OFS1_OFP2]).
-define(EP1_TO_OFS1_OFP2_BOUNDED_PATH,
        [?EP1, <<"PH1/VH2/VP0">>, <<"PH1/VP2.1">>, <<"PH1/VP1.2">>,
         <<"PH1/VH1/VP2">>, ?OFS1_OFP2]).

-define(PH1_OFS1_OFP1, <<"PH1/VH1/OFS1/OFP1">>).
-define(PH2_OFS1_OFP1, <<"PH2/VH1/OFS1/OFP1">>).
-define(PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1_PATH,
        [?PH1_OFS1_OFP1, <<"PH1/VH1/VP1">>, <<"PH1/VP1.1">>, <<"PH1/PatchP">>,
         <<"PH1/PP1">>, <<"PatchP">>, <<"PH2/PP1">>, <<"PH2/PatchP">>,
         <<"PH2/VP1.1">>, <<"PH2/VH1/VP1">>, ?PH2_OFS1_OFP1]).
-define(PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1_BOUNDED_PATH,
        [?PH1_OFS1_OFP1, <<"PH1/VH1/VP1">>, <<"PH1/VP1.1">>, <<"PH1/PP1">>,
         <<"PH2/PP1">>, <<"PH2/VP1.1">>, <<"PH2/VH1/VP1">>, ?PH2_OFS1_OFP1]).

%% Tests based on the topology shown in the figure 17A in the Lucet Desgin
%% document:
%% https://docs.google.com/document/d/1Gtoi8IX1EN3oWDRPTFa_VltOdJAwRbl_ChAZWk8oKIk/edit#
ld_fig17a_test_() ->
    {foreach, fun setup_dobby/0, fun(_) -> ok end,
     [{"Find path from EP to OFP",
       fun it_finds_path_between_ep_and_ofp/0},
      {"Bound path from EP to OFP",
       fun it_bounds_path_between_ep_and_ofp/0},
      {"Find path between OFPS",
       fun it_finds_path_between_ofps/0},
      {"Bound path between OFPS",
       fun it_bounds_path_between_ofps/0}]}.

%% Tests

it_finds_path_between_ep_and_ofp() ->
    %% GIVEN
    Src = ?EP1,
    Dst = ?OFS1_OFP2,

    % WHEN
    ActualPath0 = lucet:find_path_to_bound(Src, Dst),
    ActualPath1 = lists:map(fun({Id, _, _}) ->
                                   Id
                           end, ActualPath0),

    %% THEN
    ?assertEqual(?EP1_TO_OFS1_OFP2_PATH, ActualPath1).

it_bounds_path_between_ep_and_ofp() ->
    %% GIVEN
    Src = ?EP1,
    Dst = ?OFS1_OFP2,

    %% WHEN
    lucet:wire2(Src, Dst),

    %% THEN
    BoundedPath0 = lucet:find_path_to_bound(Src, Dst),
    BoundedPath1 = lists:map(fun({Id, _, _}) ->
                                     Id
                             end, BoundedPath0),
    ?assertEqual(?EP1_TO_OFS1_OFP2_BOUNDED_PATH, BoundedPath1).

it_finds_path_between_ofps() ->
    %% GIVEN
    Src = ?PH1_OFS1_OFP1,
    Dst = ?PH2_OFS1_OFP1,

    %% WHEN
    ActualPath0 = lucet:find_path_to_bound(Src, Dst),
    ActualPath1 = lists:map(fun({Id, _, _}) ->
                                    Id
                            end, ActualPath0),

    %% THEN
    ?assertEqual(?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1_PATH, ActualPath1).

it_bounds_path_between_ofps() ->
    %% GIVEN
    Src = ?PH1_OFS1_OFP1,
    Dst = ?PH2_OFS1_OFP1,

    %% WHEN
    lucet:wire2(Src, Dst),

    %% THEN
    BoundedPath0 = lucet:find_path_to_bound(Src, Dst),
    BoundedPath1 = lists:map(fun({Id, _, _}) ->
                                     Id
                             end, BoundedPath0),
    ?debugFmt("FOUND: ~p~n", [BoundedPath1]),
    ?assertEqual(?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1_BOUNDED_PATH, BoundedPath1).

%% Internal functions

setup_dobby() ->
    application:stop(dobby),
    {ok, _} = application:ensure_all_started(dobby),
    ok = dby_mnesia:clear(),
    ok = dby_bulk:import(json, ?JSON_FILE).
