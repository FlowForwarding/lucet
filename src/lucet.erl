-module(lucet).

-export([wire/2,
         generate_lincx_domain_config/2,
         generate_vh_domain_config/3]).

%% Diagnostics functions
-export([get_bound_to_path/2]).

-ifdef(TEST).
-compile([export_all]).
-endif.

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
-define(LINK_TYPE(V), [{_, _, ?TYPE(V)}]).
-define(LINK_TYPE2(V), [{_, _, ?TYPE(V)} | _]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Creates `bound_to` path between `SrcId' and `DstId' in Dobby.
%%
%% If `ScrId' or the path doesn't exist an error is returned.
%%
%% A `bound_to` path can only consist of:
%% 1) OpenFlow Port identifiers (lm_of_port),
%% 2) Virtual Port identifiers (lm_vp),
%% 3) Physical Port identifiers (lm_pp),
%% 4) Endpoint identifiers (endpoint),
%% 5) Patch Panel (lm_patchp).
%%
%% When a `bound_to` link is created between two ports, A and B
%% (they have to be attached to the same Patch Panel), the `wires` meta-data
%% on their Patch Panel is updated. Two entries are added to the `wires`
%% meta-data map: A => B, B => A.
%%
%% Each `bound_to` link between Physical Port and Virtual Port
%% has its corresponding xen bridge (xenbr{X} where X is a number). Before
%% wiring occurs, Physical Port is assumed to be linked  to the bridge
%% as `part of`. The wiring process is responsible for creating a `part of`
%% link between the bridge and VP.
%%
%% Each `bound_to` link between two Virtual Ports has its corresponding
%% xen bridge.  The wiring process is responsible for creating an
%% identifier for the xen bridge and its `part of` links to the Virtual Ports.
%% The bridge name is `inbr_vif{X}_vif{Y}` where X and Y are vif interfaces'
%% numbers associated with VPs that are linked.
-spec wire(dby_identifier(), dby_identifier()) -> ok | {error, term()}.

wire(SrcId, DstId) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    case find_path_to_bound(SrcId, DstId) of
        Path when is_list(Path) ->
            Bindings = bind_ports_on_patch_panel(Path),
            create_connected_to_link(SrcId, DstId),
            link_xenbrs(Bindings);
        {error, _} = Error ->
            Error
    end.

generate_lincx_domain_config(VirtualHost, MgmtIfMac) when is_list(VirtualHost) ->
    generate_lincx_domain_config(list_to_binary(VirtualHost), MgmtIfMac);
generate_lincx_domain_config(VirtualHost, MgmtIfMac) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    %% TODO: use domain config template file
    case dby:search(
	   %% First, ensure we can find the specified virtual host.
	   fun(VirtualHostId, #{<<"type">> := #{value := <<"lm_vh">>}}, [], Acc)
		 when VirtualHostId =:= VirtualHost ->
		   {continue, Acc#{virtual_host_found := true}};
	      %% A virtual port, directly connected to the virtual host.
	      (_VirtualPortId, #{<<"type">> := #{value := <<"lm_vp">>}},
	       [{VirtualHostId, #{}, #{<<"type">> := #{value := <<"part_of">>}}}],
	       Acc)
		 when VirtualHostId =:= VirtualHost ->
		   {continue, Acc};
	      %% A VIF, bound to one of our virtual ports.
	      %% Let's keep those in a list.
	      (VifId, #{<<"type">> := #{value := <<"lm_vp">>}},
	       [{_, #{<<"type">> := #{value := <<"lm_vp">>}}, #{<<"type">> := #{value := <<"bound_to">>}}},
		{VirtualHostId, #{}, #{<<"type">> := #{value := <<"part_of">>}}}],
	       Acc = #{vifs := Vifs})
		 when VirtualHostId =:= VirtualHost ->
		   {continue, Acc#{vifs := [VifId | Vifs]}};
	      %% A patch panel.  Keep going.
	      (_, #{<<"type">> := #{value := <<"lm_patchp">>}}, _, Acc) ->
		   {continue, Acc};
	      %% A physical port, linked from a patch panel, _not_
	      %% from a VIF.  Keep going.
	      %%
	      %% We need to make sure we're coming from the patch
	      %% panel, to be able to identify the patch panel to use
	      %% once we reach the physical host.
	      (_, #{<<"type">> := #{value := <<"lm_pp">>}},
	       [{_, #{<<"type">> := #{value := <<"lm_patchp">>}}, #{<<"type">> := #{value := <<"part_of">>}}} | _],
	       Acc) ->
		   {continue, Acc};
	      %% We've reached the physical host, and it has a
	      %% physical port that is part of a patch panel.  This is
	      %% the patch panel we're looking for.
	      (PhysicalHost, #{<<"type">> := #{value := <<"lm_ph">>}},
	       [{_, #{<<"type">> := #{value := <<"lm_pp">>}},
		 #{<<"type">> := #{value := <<"part_of">>}}},
		{PatchPanelId, #{<<"type">> := #{value := <<"lm_patchp">>},
				 <<"wires">> := #{value := Wires}},
		 #{<<"type">> := #{value := <<"part_of">>}}}
		| _],
	       Acc = #{patch_panel_found := false}) ->
		   {continue, Acc#{patch_panel_found := true,
				   patch_panel_id => PatchPanelId,
				   wires => Wires,
				   physical_host_id => PhysicalHost}};

	      %% Skip everything else
	      (_, _, _, Acc) ->
		   {skip, Acc}
	   end,
	   #{virtual_host_found => false,
	     patch_panel_found => false,
	     vifs => []},
	   VirtualHost,
	   %% TODO: fix max_depth
	   [breadth, {max_depth, 10}, {loop, link}]) of

	#{virtual_host_found := false} ->
	    io:format(standard_error, "Virtual host '~s' not found~n", [VirtualHost]),
	    {error, virtual_host_not_found};

	#{patch_panel_found := false} ->
	    io:format(standard_error, "Patch panel not found~n", []),
	    {error, patch_panel_not_found};

	#{patch_panel_id := _PatchPanelId,
	  wires := Wires,
	  vifs := Vifs,
	  physical_host_id := _PhysicalHost} ->
	    %% TODO: match up virtual ports to bridge interfaces.
	    %% Probably need to extract from Dobby.
	    FirstVif = {MgmtIfMac, <<"xenbr0">>},
	    MgmtIfMacNo = mac_string_to_number(MgmtIfMac),
	    OtherVifs = find_xen_bridges_for_vh_vps(Vifs, Wires),
	    VifList = [FirstVif] ++ lists:usort(OtherVifs),
	    VifString = "vif = [" ++
		string:join([begin
				 {_Ph, If} = split_identifier_into_prefix_and_rest(PhIf),
				 "'" ++ case Mac of
					    undefined -> "";
					    _ -> "mac=" ++ Mac ++ ","
					end ++
				     "bridge=" ++ If ++ "'"
			     end || {Mac, PhIf} <- VifList],
			    ",\n       ") ++
		"]\n",
	    io:format("~s~n", [VifString]),
	    ok
    end.

%% @doc Generate domain config file for Xen.
%%
%% The `PhysicalHost' is the Physical Host identifier with Virtual Hosts
%% for which the config is to be generated. Then `VhNo' is the Virtual Host
%% number.  The `MgmtIfMac' is the Mac address of the management interface
%% attached to the VH.
%%
%% For example, to get the domain config file for "PH1/VH1" if the Management
%% Interface for the VH has "00:00:00:00:AB:01" Mac address, one need to call:
%% `generate_vh_domain_config(<<"PH1">>, 1, "00:00:00:00:AB:01")'.
-spec generate_vh_domain_config(dby_identifier(), integer(), string()) ->
                                       string() | {error, term()}.

generate_vh_domain_config(PhysicalHost, VhNo, MgmtMac) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    Vifs = collect_vifs_identifiers_for_vh_no(binary_to_list(PhysicalHost),
                                              VhNo),
    try
        Xenbrs = collect_xenbrs_with_macs_for_vifs(Vifs),
        VifString = generate_vif_string(MgmtMac, Xenbrs),
        io:format("~s~n", [VifString]),
        VifString
    catch
        throw:Error ->
            {error, Error}
    end.

-spec get_bound_to_path(dby_identifier(), dby_identifier()) ->
                               [dby_identifier()] | not_found.

get_bound_to_path(Src, Dst) ->
    Fun = fun(Id, _, _, Acc) when Id =:= Src ->
                  {continue, Acc};
             (Id, _, Path0, _) when Id =:= Dst ->
                  Path1 = lists:foldl(fun({PathId, _Md, _LkType}, Acc) ->
                                      [PathId | Acc]
                                      end, [], Path0),
                  {stop, [Id | lists:reverse(Path1)]};
             (_Id, _, ?LINK_TYPE(<<"bound_to">>), Acc) ->
                  {continue, Acc};
             (_Id, _, ?LINK_TYPE2(<<"bound_to">>), Acc) ->
                  {continue, Acc};
             (_Id, _, _, Acc) ->
                  {skip, Acc}
          end,
    dby:search(Fun, not_found, Src, [breadth, {max_depth, 100}]).

%%%===================================================================
%%% Internal functions
%%%===================================================================

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

%% @doc Finds a path between two identifiers to be bound.
%%
%% This function returns a list of identifiers between `SrcId' and `DstId'
%% in the order as they appear in Dobby. The identifiers can be
%% one of the following:
%% 1) OpenFlow Port identifiers (lm_of_port),
%% 2) Virtual Port identifiers (lm_vp),
%% 3) Physical Port identifiers (lm_pp),
%% 4) Endpoint identifiers (endpoint),
%% 5) Patch Panel (lm_patchp).
%%
%% A links between those identifiers are expected to be of type `bound_to`
%% apart from Patch Panel identifiers which are linked via `part_of`
%% with other identifiers.
-spec find_path_to_bound(dby_identifier(), dby_identifier()) ->
                                        Result when
      Result :: [{Id :: dby_identifier(),
                  IdMetadata :: metadata_info(),
                  LinkMetadata :: metadata_info()}]
              | {start_node_not_found, dby_identifier()}.

find_path_to_bound(SrcId, DstId) ->
    case dby:search(find_path_to_bound_dby_fun(DstId),
		    {start_node_not_found, SrcId},
		    SrcId,
		    [breadth, {max_depth, 100}]) of
	{start_node_not_found, _} = Error ->
	    {error, Error};
        [] ->
            {error, {path_to_bound_not_found, SrcId, DstId}};
	Path when is_list(Path) ->
            Path
    end.

%% @doc Finds a path to bound that ends on `DstId'.
find_path_to_bound_dby_fun(DstId) ->
    fun(_, #{<<"type">> := #{value := Type}}, _, Acc) when
              Type =:= <<"lm_ph">> orelse
              Type =:= <<"lm_vh">> orelse
              Type =:= <<"of_Switch">> ->
            {skip, Acc};
       (_, _, [], _Acc) ->
            %% The first node (path is empty).
            %% Forget {start_node_not_found, SrcId}.
            {continue, []};
       (_, ?TYPE(<<"lm_patchp">>) = Md, [{PortId, _, _} | _], Acc) ->
            #{<<"wires">> := #{value := Wires}} = Md,
            case is_port_attached_to_patchp_bounded(Wires, PortId) of
                true ->
                    %% if the port is bounded, follow 'bound_to' path
                    {skip, Acc};
                false ->
                    {continue, Acc}
            end;
       (Id, Md, Path, _) when Id =:= DstId ->
            {stop, lists:reverse([{Id, Md, #{}} | Path])};
       (_, _, _, Acc) ->
            {continue, Acc}
    end.

create_connected_to_link(SrcId, DstId) ->
    ok = dby:publish(<<"lucet">>, SrcId, DstId,
                     [{<<"type">>, <<"connected_to">>}],
                     [persistent]).

%% @doc Sets up identifiers for xen bridges in Dobby.
%%
%% The functions takes a list of bindings that were published into the
%% Dobby. A `Binding' is associated with a `bound_to' link that was published
%% for two port attached to the same Patch Panel. For each such a `Binding'
%% a xen bridge identifier needs to be set up appropriately.
%%
%% Each `bound_to` link between Physical Port and Virtual Port
%% has its corresponding xen bridge (xenbr{X} where X is a number). Before
%% wiring occurs, Physical Port is assumed to be linked  to the bridge
%% as `part of`. The wiring process is responsible for creating a `part of`
%% link between the bridge and VP.
%%
%% Each `bound_to` link between two Virtual Ports has its corresponding
%% xen bridge.  The wiring process is responsible for creating an
%% identifier for the xen bridge and its `part of` links to the Virtual Ports.
%% The bridge name is `inbr_vif{X}_vif{Y}` where X and Y are vif interfaces'
%% numbers associated with VPs that are linked.
-spec link_xenbrs([Binding]) -> ok when
      Binding :: [{PathElement, PathElement, PathElement}],
      PathElement :: {Id :: dby_identifier(),
                      IdMetadata :: metadata_info(),
                      LinkMetadata :: metadata_info()}.

link_xenbrs([{
               {_PatchpId, ?TYPE(<<"lm_patchp">>), _},
               {P1Id, #{<<"type">> := #{value := P1Type}}, _},
               {P2Id, #{<<"type">> := #{value := P2Type}}, _}
             } | Rest]) ->
    {XenbrId, LinkTo} = case {P1Type, P2Type} of
                            {<<"lm_pp">>, <<"lm_pp">>} ->
                                {no_xenbr_between_physical_ports, []};
                            {<<"lm_pp">>, _} ->
                                {find_xenbr_vp_for_physical_port(P1Id),
                                 [P2Id]};
                            {_, <<"lm_pp">>} ->
                                {find_xenbr_vp_for_physical_port(P2Id),
                                 [P1Id]};
                            _ ->
                                %% PhId = find_patchp_ph(PatchpId),
                                {publish_inbr_for_ph(P1Id, P2Id),
                                 [P1Id, P2Id]}
                        end,
    link_xenbrs(XenbrId, LinkTo),
    link_xenbrs(Rest);
link_xenbrs([_Other | Rest]) ->
    link_xenbrs(Rest);
link_xenbrs([]) ->
    ok.

publish_inbr_for_ph(P1Id, P2Id) ->
    {Prefix, Rest1} = split_identifier_into_prefix_and_rest(P1Id),
    {Prefix, Rest2} = split_identifier_into_prefix_and_rest(P2Id),
    InbrId0 = io_lib:format("~s/inbr_~s_~s",
                            [Prefix | lists:sort([Rest1, Rest2])]),
    InbrId1 = re:replace(InbrId0, "VP", "vif", [global, {return, binary}]),
    ok = dby:publish(<<"lucet">>, {InbrId1, [{<<"type">>, <<"lm_vp">>}]},
                     [persistent]),
    InbrId1.

find_xenbr_vp_for_physical_port(Port) ->
    Fun = fun(XenbrVpId, ?TYPE(<<"lm_vp">>),
              [{_, _, ?TYPE(<<"part_of">>)}], _) ->
                  {stop, XenbrVpId};
             (Id, _, _, Acc) when Id =:= Port ->
                  {continue, Acc};
             (_, _, _, Acc) ->
                  {skip, Acc}
          end,
    dby:search(Fun, not_found, Port, [breadth, {max_depth, 1}]).

link_xenbrs(_, []) ->
    ok;
link_xenbrs(XenbrId, Ports) ->
    [ok = dby:publish(<<"lucet">>, XenbrId, P, [{<<"type">>, <<"part_of">>}],
                      [persistent]) || P <- Ports].


bind_ports_on_patch_panel(Path) ->
    bind_ports_on_patch_panel(Path, []).

%% @doc Creates `bound_to` links and return new bindings.
%%
%% `Path' is expected to be a list of tuples containing identifier,
%% its metadata and link metadata that led to this identifier while searching
%% for a path to be bound. The tuples are ordered as they appear in Dobby.
%% The identifiers can be one of the following:
%% 1) OpenFlow Port identifiers (lm_of_port),
%% 2) Virtual Port identifiers (lm_vp),
%% 3) Physical Port identifiers (lm_pp),
%% 4) Endpoint identifiers (endpoint),
%% 5) Patch Panel (lm_patchp).
%%
%% This function looks for Patch Panel identifiers and creates a `bound_to`
%% link between its two neighbouring ports.
%%
%% It allso accumulates newly created bindings that are returned.
-spec bind_ports_on_patch_panel([PathElement]) -> Bindings when
      PathElement :: {Id :: dby_identifier(),
                      IdMetadata :: metadata_info(),
                      LinkMetadata :: metadata_info()},
      Bindings :: [{PathElement, PathElement, PathElement}].

bind_ports_on_patch_panel([{P1Id, _, _} = PortA,
                           {PatchpId, ?TYPE(<<"lm_patchp">>), _} = Patchp,
                           {P2Id, _, _} = PortB | Rest], Bindings) ->
    bind_ports_on_patch_panel(PatchpId, P1Id, P2Id),
    bind_ports_on_patch_panel([PortB | Rest],
                              [{Patchp, PortA, PortB} | Bindings]);
bind_ports_on_patch_panel([], Bindings) ->
    Bindings;
bind_ports_on_patch_panel([_ | Rest], Bindings) ->
    bind_ports_on_patch_panel(Rest, Bindings).

%% @doc Bounds `PortA' with `PortB' that exists on `PatchPId'.
%%
%% It creates a bound_to link from `PortA' to `PortB' and updates
%% wires metadata on the `PathchpId' indicating that the `PortA' and `PortB'
%% are connected.
bind_ports_on_patch_panel(PatchpId, PortA, PortB) ->
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

split_identifier_into_prefix_and_rest(Identifier) ->
    IdentifierS = binary_to_list(Identifier),
    case string:tokens(IdentifierS, "/") of
        IdentifierS ->
            "";
        Tokens0 ->
            Tokens1 = lists:droplast(Tokens0),
            {string:join(Tokens1, "/"), hd(lists:reverse(Tokens0))}
    end.

%% @priv This function relies on the fact, that the Vif interfaces'
%% identifiers are based on on pattern: {PH_IDENTIFIER}/VP{VH_NO}.{VIF_NO}.
collect_vifs_identifiers_for_vh_no(PhysicalHost, VhNo) ->
    VifPrefix = PhysicalHost ++ "/VP" ++ integer_to_list(VhNo) ++ ".",
    collect_vifs_identifiers_for_vh_no(VifPrefix, _FirstVifNo = 1, []).

collect_vifs_identifiers_for_vh_no(_, stop, Acc) ->
    Acc;
collect_vifs_identifiers_for_vh_no(VifPrefix, VifNo, Acc) ->
    Identifier = list_to_binary(VifPrefix ++ integer_to_list(VifNo)),
    case dby:identifier(Identifier) of
        [] ->
            collect_vifs_identifiers_for_vh_no(VifPrefix, stop, Acc);
        #{} = _Found ->
            collect_vifs_identifiers_for_vh_no(VifPrefix, VifNo + 1,
                                               [Identifier | Acc])
    end.

collect_xenbrs_with_macs_for_vifs(Vifs) ->
    [case dby:search(mk_find_xenbr_for_bound_ports(Vif), not_found, Vif,
                     [{max_depth, 2}]) of
         {found, XenbrId} ->
             {_, XenbrName} = split_identifier_into_prefix_and_rest(XenbrId),
             {_Mac = undefined, XenbrName};
         not_found ->
             throw({xenbr_for_vif_not_found, Vif})
     end || Vif <- Vifs].

%% @priv This function finds Virtual Port identifier corresponding to
%% a Xen bridge that connects two bound ports.
%$
%% It relies on the fact that two bound ports are 'part_of' the Xen bridge
%% identifier, and those bound ports are directly connected to each other.
mk_find_xenbr_for_bound_ports(VpId) ->
    fun(Id, _, [], Acc) when Id =:= VpId ->
            {continue, Acc};
       (Id,
        #{<<"type">> := #{value := <<"lm_vp">>}},
        [{_, _, #{<<"type">> := #{value := <<"part_of">>}}}],
        _Acc) ->
            {stop, {found, Id}};
       (_, _, _, Acc) ->
            {skip, Acc}
    end.

generate_vif_string(MgmtIfMac, Xenbrs) ->
    FirstVif = {MgmtIfMac, "xenbr0"},
    "vif = [" ++
        string:join([begin
                         "'" ++ case Mac of
                                    undefined -> "";
                                    _ -> "mac=" ++ Mac ++ ","
                                end ++
                             "bridge=" ++ Xenbr ++ "'"
                     end || {Mac, Xenbr} <- [FirstVif | Xenbrs]],
                    ",\n       ") ++
        "]\n".

is_port_attached_to_patchp_bounded(Wires, PortId) ->
    %% A port is considered bound if it is present in the wires map
    %% and not <<"null">>.
    maps:get(PortId, Wires, <<"null">>) =/= <<"null">>.


find_xen_bridges_for_vh_vps(Vifs, Wires) ->
    lists:foldl(
      fun({Port1, Port2}, Acc) ->
              case find_vp_linked_to_ports_as_part_of(Port1, Port2) of
                  not_found ->
                      io:format(standard_error, "Cannot find port ~s in Dobby~n", [Port1]),
                      Acc;
                  {found, BridgeId} ->
                      %% TODO: find MAC address
                      [{undefined, BridgeId}] ++ Acc;
                  [] ->
                      io:format(standard_error, "No bridge interface linked to ~s~n", [Port1]),
                      Acc;
                  [_|_] = MaybeBridges ->
                      io:format(standard_error, "No bridge interface linked to both ~s and ~s (looked at ~p)~n",
                                [Port1, Port2, MaybeBridges]),
                      Acc
              end
      end, [], [{VP, maps:get(VP, Wires)}
                || VP <- Vifs, maps:get(VP, Wires, <<"null">>) =/= <<"null">>]).

find_vp_linked_to_ports_as_part_of(Port1, Port2) ->
    Fun = fun(_, _, [], _Acc) ->
                  {continue, []};
             (Id, #{<<"type">> := #{value := <<"lm_vp">>}},
              [{LinkedFrom, _, #{<<"type">> := #{value := <<"part_of">>}}}],
              MaybeBridges) when LinkedFrom =:= Port1 ->
                  %% This is a virtual port that is
                  %% part_of Port1.  Save it as a
                  %% candidate.
                  {continue, [Id | MaybeBridges]};
             (Id, #{},
              [{LinkedFrom, _, #{<<"type">> := #{value := <<"bound_to">>}}}],
              MaybeBridges) when LinkedFrom =:= Port1, Id =:= Port2 ->
                  %% We found Port2 directly from Port1.  Keep going.
                  {continue, MaybeBridges};
             (Id, #{<<"type">> := #{value := <<"lm_vp">>}},
              [{LinkedFromPort2, _, #{<<"type">> := #{value := <<"part_of">>}}},
               {LinkedFromPort1, _, #{<<"type">> := #{value := <<"bound_to">>}}}],
              MaybeBridges) when LinkedFromPort2 =:= Port2, LinkedFromPort1 =:= Port1 ->
                  %% This is a virtual port that is
                  %% part_of Port2.
                  case lists:member(Id, MaybeBridges) of
                      true ->
                          %% It's also part_of Port1.
                          %% This is the one we want.
                          {stop, {found, Id}};
                      false ->
                          %% Keep looking.
                          {continue, MaybeBridges}
                  end;
             (Id, #{},
              [{LinkedFromBridge, _, #{<<"type">> := #{value := <<"part_of">>}}},
               {LinkedFromPort1, _, #{<<"type">> := #{value := <<"part_of">>}}}],
              MaybeBridges) when Id =:= Port2, LinkedFromPort1 =:= Port1 ->
                  %% We found Port2 through a
                  %% virtual port that might be
                  %% part_of Port1.
                  case lists:member(LinkedFromBridge, MaybeBridges) of
                      true ->
                          {stop, {found, LinkedFromBridge}};
                      false ->
                          {skip, MaybeBridges}
                  end;
             (_, _, _, MaybeBridges) ->
                  %% Skip everything else.
                  {skip, MaybeBridges}
          end,
    dby:search(Fun, not_found, Port1, [breadth, {max_depth, 3}, {loop, link}]).




