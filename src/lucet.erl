-module(lucet).

-export([wire/2,
         wire2/2,
         generate_lincx_domain_config/2,
         generate_vm_domain_config/2]).

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


%% API

wire(Endpoint, OFPort) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    ok = connect_endpoint_with_of_port(Endpoint, OFPort),
    generate_domain_config_and_run_vm().

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
	      %% Let's keep those in a list.
	      (VirtualPortId, #{<<"type">> := #{value := <<"lm_vp">>}},
	       [{VirtualHostId, #{}, #{<<"type">> := #{value := <<"part_of">>}}}],
	       Acc = #{virtual_ports := VirtualPorts})
		 when VirtualHostId =:= VirtualHost ->
		   {continue, Acc#{virtual_ports := [VirtualPortId | VirtualPorts]}};
	      %% A VIF, bound to one of our virtual ports.
	      (_, #{<<"type">> := #{value := <<"lm_vp">>}},
	       [{_, #{<<"type">> := #{value := <<"lm_vp">>}}, #{<<"type">> := #{value := <<"bound_to">>}}},
		{VirtualHostId, #{}, #{<<"type">> := #{value := <<"part_of">>}}}],
	       Acc)
		 when VirtualHostId =:= VirtualHost ->
		   {continue, Acc};
	      %% A patch panel.  Keep going.
	      (_, #{<<"type">> := #{value := <<"lm_patchp">>}}, _, Acc) ->
		   {continue, Acc};
	      %% A physical port.  Keep going.
	      (_, #{<<"type">> := #{value := <<"lm_pp">>}}, _, Acc) ->
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
	     virtual_ports => []},
	   VirtualHost,
	   %% TODO: fix max_depth
	   [breadth, {max_depth, 10}]) of

	#{virtual_host_found := false} ->
	    io:format(standard_error, "Virtual host '~s' not found~n", [VirtualHost]),
	    {error, virtual_host_not_found};

	#{patch_panel_found := false} ->
	    io:format(standard_error, "Patch panel not found~n", []),
	    {error, patch_panel_not_found};

	#{patch_panel_id := PatchPanelId,
	  wires := Wires,
	  virtual_ports := VirtualPorts,
	  physical_host_id := PhysicalHost} ->
	    %% TODO: match up virtual ports to bridge interfaces.
	    %% Probably need to extract from Dobby.
	    FirstVif = {MgmtIfMac, "xenbr0"},
	    MgmtIfMacNo = mac_string_to_number(MgmtIfMac),
	    OtherVifs =
		maps:fold(
		  fun(_Port1, <<"null">>, Acc) ->
			  Acc;
		     (Port1, Port2, Acc) ->
			  case re:run(Port1, <<"^", PhysicalHost/binary, "/PP([0-9]+)$">>, [{capture, all_but_first, list}]) of
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
	    ok
    end.

generate_vm_domain_config(PhysicalHost, VmNo) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    VmVif = string:join([PhysicalHost, "VP" ++ integer_to_list(VmNo) ++ ".1"],
                        "/"),
    case dby:search(
           fun(_, _, [], Acc) ->
                   {continue, Acc};
              (Id,
               #{<<"type">> := #{value := <<"lm_vp">>}},
               [{_, _, #{<<"type">> := #{value := <<"part_of">>}}}],
               _Acc) ->
                   {stop, {found, Id}};
              (_, _, _, Acc) ->
                   {skip, Acc}
           end,
           not_found,
           list_to_binary(VmVif),
           [{max_depth, 2}]) of
        {found, InxenbrId} ->
            VifString = "vif = ['bridge="
                ++ "xenbr" ++ integer_to_list(100 + VmNo) ++ "'" ++
                "]\n",
            io:format("~s~n", [VifString]);
        not_found ->
            io:format(standard_error, "Bridge for VM vif ~s not found in dobby!~n",
                      [VmVif]),
            {error, not_found}
    end.

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
	{start_node_not_found, _} = Error ->
	    {error, Error};
        {not_found, ToPatchp0} ->
            ToPatchp = filter_out_md(ToPatchp0),
            Patchp = lists:last(ToPatchp),
            FromPatchp0 = search_path_from_patchp_to_of_port(Patchp, OFPort),
            assert_from_patchp_path_exists(FromPatchp0),
            FromPatchp = filter_out_md(FromPatchp0),
            {PortA, PortB} =
                ports_to_be_connected(ToPatchp ++ tl(FromPatchp), Patchp),
            bind_ports_on_patch_panel(Patchp, PortA, PortB),
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
    fun(_Id, ?TYPE(<<"endpoint">>), [], _Acc) ->
            %% At this point, Acc contains {start_node_not_found, Id}.
            %% Time to overwrite that.
            {continue, []};
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

search_bound_path_from_endpoint_to_of_port(Endpoint, OFPort) ->
    dby:search(get_bound_path_from_endpoint_fun(OFPort),
               {start_node_not_found, Endpoint},
               Endpoint,
               [breadth, {max_depth, 100}]).

search_path_from_patchp_to_of_port(PatchP, OFPort) ->
    dby:search(get_bound_path_from_patchp_fun(OFPort),
               not_found,
               PatchP,
               [breadth, {max_depth, 100}]).

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
	    Error;
	Path when is_list(Path) ->
	    filter_patch_panels_on_path(Path, [])
            %% TODO: add case for empy list and return empty path error
    end.

%% @doc Filters patch panels between connected ports
%% TODO: TO be removed
filter_patch_panels_on_path([{P1Id, _, _} = PortA,
                             {_Id, ?TYPE(<<"lm_patchp">>) = PatchPMd, _} = PatchP,
                             {P2Id, _, _} = PortB | Rest], Acc) ->
    #{<<"wires">> := #{value := WiresMap}} = PatchPMd,
    case maps:get(P1Id, WiresMap) of
        P2Id ->
            %% The ports are connected; PatchP have to be removed from path
            filter_patch_panels_on_path(Rest, [PortB, PortA | Acc]);
        _ ->
            filter_patch_panels_on_path(Rest, [PortB, PatchP, PortA | Acc])
    end;
filter_patch_panels_on_path([], Acc) ->
    lists:reverse(Acc);
filter_patch_panels_on_path([Other | Rest], Acc) ->
    filter_patch_panels_on_path(Rest, [Other | Acc]).

%% @doc Finds a path to bound that ends on `DstId'.
%%
%% TODO: Check wires MD
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
       (Id, Md, Path, _) when Id =:= DstId ->
            {stop, lists:reverse([{Id, Md, #{}} | Path])};
       (_, _, _, Acc) ->
            {continue, Acc}
    end.

%% @doc Creates `bound to` path between `SrcId' and `DstId' in Dobby.
%%
%% If `ScrId' or the path doesn't exist an error is returned.
%%
%% A `bound to` path can only consist of:
%% 1) OpenFlow Port identifiers (lm_of_port),
%% 2) Virtual Port identifiers (lm_vp),
%% 3) Physical Port identifiers (lm_pp),
%% 4) Endpoint identifiers (endpoint),
%% 5) Patch Panel (lm_patchp).
%%
%% When a `bound to` link is created between two ports, A and B
%% (they have to be attached to the same Patch Panel), the `wires` meta-data
%% on their Patch Panel is updated. Two entries are added to the `wires`
%% meta-data map: A => B, B => A.
%%
%% Each `bound to` link between Physical Port and Virtual Port
%% has its corresponding xen bridge (xenbr{X} where X is a number). Before
%% wiring occurs, Physical Port is assumed to be linked  to the bridge
%% as `part of`. The wiring process is responsible for creating a `part of`
%% link between the bridge and VP.
%%
%% Each `bound to` link between two Virtual Ports has its corresponding
%% xen bridge.  The wiring process is responsible for creating an
%% identifier for the xen bridge and its `part of` links to the Virtual Ports.
%% The bridge name is `inbr_vif{X}_vif{Y}` where X and Y are vif interfaces'
%% numbers associated with VPs that are linked.
-spec wire2(dby_identifier(), dby_identifier()) -> ok | {error, term()}.

wire2(SrcId, DstId) ->
    global:sync(),
    {module, _} = dby:install(?MODULE),
    case find_path_to_bound(SrcId, DstId) of
	{start_node_not_found, _} = Error ->
	    {error, Error};
	Path when is_list(Path) ->
            Path = find_path_to_bound(SrcId, DstId),
            Bindings = bind_ports_on_patch_panel(Path),
            create_connected_to_link(SrcId, DstId),
            link_xenbrs(Bindings)
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
%% Each `bound to` link between Physical Port and Virtual Port
%% has its corresponding xen bridge (xenbr{X} where X is a number). Before
%% wiring occurs, Physical Port is assumed to be linked  to the bridge
%% as `part of`. The wiring process is responsible for creating a `part of`
%% link between the bridge and VP.
%%
%% Each `bound to` link between two Virtual Ports has its corresponding
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
               {PatchpId, ?TYPE(<<"lm_patchp">>), _},
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
                                PhId = find_patchp_ph(PatchpId),
                                {publish_xenbr_for_ph(PhId),
                                 [P1Id, P2Id]}
                        end,
    link_xenbrs(XenbrId, LinkTo),
    link_xenbrs(Rest);
link_xenbrs([_Other | Rest]) ->
    link_xenbrs(Rest);
link_xenbrs([]) ->
    ok.

publish_xenbr_for_ph(PhId) ->
    Id = list_to_binary(erlang:ref_to_list(make_ref())),
    XenbrId = <<PhId/binary, "/", "INXEN", "/", Id/binary>>,
    ok = dby:publish(<<"lucet">>, {XenbrId, [{<<"type">>, <<"lm_vp">>}]},
                     [persistent]),
    XenbrId.

str_time() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} =
        calendar:now_to_datetime(erlang:now()),
    lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w",
                                [Year,Month,Day,Hour,Minute,Second])).

find_patchp_ph(PatchpId) ->
    PatchpIdS = binary_to_list(PatchpId),
    Tokens0 = string:tokens(PatchpIdS, "/"),
    Tokens1 = lists:droplast(Tokens0),
    list_to_binary(string:join(Tokens1, "/")).

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
    bind_ports_on_patch_panel(PatchpId, PortA, PortB),

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

