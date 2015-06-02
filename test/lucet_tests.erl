-module(lucet_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").

%% Topo generated using the following command:
%% ./utils/appfest_gen -out lucet_design_fig_17_A.json -physical_ports 1 \
%% -ofp_ports 2 -virtual_hosts 1 -physical_hosts 2
-define(JSON_FILE, "../lucet_design_fig_17_A.json").

-define(EP1, <<"PH1/VH2/EP1">>).
-define(OFS1_OFP2, <<"PH1/VH1/OFS1/OFP2">>).
-define(EP1_TO_PH1_OFS1_OFP2,
        [?EP1, <<"PH1/VH2/VP0">>, <<"PH1/VP2.1">>, <<"PH1/PatchP">>,
         <<"PH1/VP1.2">>, <<"PH1/VH1/VP2">>, ?OFS1_OFP2]).

-define(PH1_OFS1_OFP1, <<"PH1/VH1/OFS1/OFP1">>).
-define(PH2_OFS1_OFP1, <<"PH2/VH1/OFS1/OFP1">>).
-define(PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1,
        [?PH1_OFS1_OFP1, <<"PH1/VH1/VP1">>, <<"PH1/VP1.1">>, <<"PH1/PatchP">>,
         <<"PH1/PP1">>, <<"PatchP">>, <<"PH2/PP1">>, <<"PH2/PatchP">>,
         <<"PH2/VP1.1">>, <<"PH2/VH1/VP1">>, ?PH2_OFS1_OFP1]).

-define(BOUNDED(X),lists:filter(fun(IdBin) ->
                                        Id = binary_to_list(IdBin),
                                        not lists:suffix("PatchP", Id)
                                end, X)).

-define(TYPE(V), #{<<"type">> := #{value := V}}).
-define(LINK_TYPE(V), [{_, _, ?TYPE(V)}]).

%% Tests based on the topology shown in the figure 17A in the Lucet Desgin
%% document:
%% https://docs.google.com/document/d/1Gtoi8IX1EN3oWDRPTFa_VltOdJAwRbl_ChAZWk8oKIk/edit#
ld_fig17a_test_() ->
    {foreach, fun setup_dobby/0, fun(_) -> ok end,
     [
      {"Find path from EP to OFP",
       fun it_finds_path_between_ep_and_ofp/0},
      {"Bound path from EP to OFP",
       fun it_binds_path_between_ep_and_ofp/0},
      {"Bound already bounded path from EP to OFP",
       fun it_binds_already_bounded_path_between_ep_and_ofp/0},
      {"Find path between OFPS",
       fun it_finds_path_between_ofps/0},
      {"Bound path between OFPS",
       fun it_binds_path_between_ofps/0},
      {"Bound already bounded path between OFPS",
       fun it_binds_already_bounded_path_between_ofps/0}
     ]}.

%% Tests

it_finds_path_between_ep_and_ofp() ->
    %% GIVEN
    Src = ?EP1,
    Dst = ?OFS1_OFP2,

    % WHEN
    Path = find_path_to_be_bound(Src, Dst),

    %% THEN
    ?assertEqual(?EP1_TO_PH1_OFS1_OFP2, Path).

it_binds_path_between_ep_and_ofp() ->
    %% GIVEN
    Src = ?EP1,
    Dst = ?OFS1_OFP2,

    %% WHEN
    ok = lucet:wire2(Src, Dst),

    %% THEN
    assert_src_connected_to_dst(Src, Dst),
    assert_path_bounded(Src, Dst, ?EP1_TO_PH1_OFS1_OFP2),
    assert_xnebrs_setup(?EP1_TO_PH1_OFS1_OFP2),
    assert_patch_panels_wired(?EP1_TO_PH1_OFS1_OFP2).

it_binds_already_bounded_path_between_ep_and_ofp() ->
    %% GIVEN
    Src = ?EP1,
    Dst = ?OFS1_OFP2,

    %% WHEN
    ok = lucet:wire2(Src, Dst),

    %% THEN
    ?assertEqual(ok, lucet:wire2(Src, Dst)),
    assert_path_bounded(Src, Dst, ?EP1_TO_PH1_OFS1_OFP2).

it_finds_path_between_ofps() ->
    %% GIVEN
    Src = ?PH1_OFS1_OFP1,
    Dst = ?PH2_OFS1_OFP1,

    %% WHEN
    Path = find_path_to_be_bound(Src, Dst),

    %% THEN
    ?assertEqual(?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1, Path).

it_binds_path_between_ofps() ->
    %% GIVEN
    Src = ?PH1_OFS1_OFP1,
    Dst = ?PH2_OFS1_OFP1,

    %% WHEN
    ok = lucet:wire2(Src, Dst),

    %% THEN
    assert_src_connected_to_dst(Src, Dst),
    assert_path_bounded(Src, Dst, ?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1),
    assert_xnebrs_setup(?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1),
    assert_patch_panels_wired(?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1).

it_binds_already_bounded_path_between_ofps() ->
    %% GIVEN
    Src = ?PH1_OFS1_OFP1,
    Dst = ?PH2_OFS1_OFP1,

    %% WHEN
    ok = lucet:wire2(Src, Dst),

    %% THEN
    ?assertEqual(ok, lucet:wire2(Src, Dst)),
    assert_path_bounded(Src, Dst, ?PH1_OFS1_OFP1_TO_PH2_OFS1_OFP1).

%% Assertions

assert_src_connected_to_dst(Src, Dst) ->
    Links = dby:links(Src),
    ?assertMatch({Dst, ?TYPE(<<"connected_to">>)},
                 lists:keyfind(Dst, 1, Links)).

assert_path_bounded(Src, Dst, ExpectedPath) ->
    Fun = fun(_, #{<<"type">> := #{value := Type}}, _, Acc) when
              Type =:= <<"lm_ph">> orelse
              Type =:= <<"lm_vh">> orelse
              Type =:= <<"of_Switch">> ->
            {skip, Acc};
       (Id, Md, [{_, _, #{<<"type">> := #{value := LinkT}}} | _ ] = Path, Acc)
          when Id =:= Dst ->
            case LinkT of
                <<"connected_to">> ->
                    {skip, Acc};
                <<"bound_to">> ->
                    {stop, lists:reverse([{Id, Md, #{}} | Path])}
            end;
       (_, _, _, Acc) ->
            {continue, Acc}
    end,
    Path = dby:search(Fun, not_found, Src,
                      [breadth, {max_depth, 100}, {loop, link}]),
    ?assertEqual(?BOUNDED(ExpectedPath), lists:map(fun({Id, _, _}) -> Id end,
                                                   Path)).

assert_xnebrs_setup(UnboundedPath) ->
    PatchPanelsWires = construct_expected_patch_panels_wires(UnboundedPath),
    lists:foreach(
      fun({_PatchpId, PortA, PortB}) ->
              not (is_id_physical_port(PortA) andalso is_id_physical_port(PortB))
                  andalso assert_xenbr_between_ports(PortA, PortB)
      end, PatchPanelsWires).

assert_xenbr_between_ports(PortA, PortB) ->
    Fun = fun(Id, _, _, Acc) when Id =:= PortA ->
                  {continue, Acc};
             (Id, _, Path, Acc) when Id =:= PortB ->
                  case length(Path) of
                      1 ->
                          %% PortB reached directly from PortA
                          {skip, Acc};
                      2 ->
                          %% PortB reached via xenbr identifier
                          {stop, found}
                  end;
             %% If we are not in the start identifer or in the destination
             %% we can only move to the xenbr virtual port
             (_, ?TYPE(<<"lm_vp">>), ?LINK_TYPE(<<"part_of">>), Acc) ->
                  {continue,  Acc};
             (_, _, _, Acc) ->
                  {skip, Acc}
          end,
    ?assertEqual(found, dby:search(Fun, not_found, PortA,
                                   [breadth, {max_depth, 2}, {loop, link}])).

assert_patch_panels_wired(UnboundedPath) ->
    PatchPanelsWires = construct_expected_patch_panels_wires(UnboundedPath),
    lists:foreach(fun({PatchpId, PortA, PortB}) ->
                          ActualWires = find_patch_panel_wires(PatchpId),
                          ?assertEqual(PortB, maps:get(PortA, ActualWires)),
                          ?assertEqual(PortA, maps:get(PortB, ActualWires))
                  end, PatchPanelsWires).

%% Internal functions

setup_dobby() ->
    application:stop(dobby),
    {ok, _} = application:ensure_all_started(dobby),
    ok = dby_mnesia:clear(),
    ok = dby_bulk:import(json, ?JSON_FILE).

find_path_to_be_bound(Src, Dst) ->
    Path = lucet:find_path_to_bound(Src, Dst),
    lists:map(fun({Id, _, _}) -> Id end, Path).

construct_expected_patch_panels_wires(UnboundedPath) ->
    construct_expected_patch_panels_wires(UnboundedPath, [], []).

construct_expected_patch_panels_wires([IdBin | Rest], Passed, Wires0) ->
    Id = binary_to_list(IdBin),
    Wires1 = case lists:suffix("PatchP", Id) of
                 true ->
                     PortA = hd(Passed),
                     PortB = hd(Rest),
                     [{IdBin, PortA, PortB} | Wires0];
                 false ->
                     Wires0
             end,
    construct_expected_patch_panels_wires(Rest, [IdBin | Passed], Wires1);
construct_expected_patch_panels_wires([], _, Wires) ->
    Wires.

find_patch_panel_wires(PatchpId) ->
    Fun = fun(_, ?TYPE(<<"lm_patchp">>) = Md, _, _) ->
                  #{<<"wires">> := #{value := Wires}} = Md,
                  {stop, Wires}
          end,
    dby:search(Fun, not_found, PatchpId, [breadth, {max_depth, 0}]).

is_id_physical_port(Id) ->
    find_identifier_type(Id) =:= <<"lm_pp">>.

find_identifier_type(Id) ->
    Fun = fun(_, #{<<"type">> := #{value := V}} , _, _) ->
                  {stop, V}
          end,
    dby:search(Fun, not_found, Id, [breadth, {max_depth, 0}]).

