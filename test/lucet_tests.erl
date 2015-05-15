-module(lucet_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("dobby_clib/include/dobby.hrl").

%% Topo generated ussing the following command:
%% ./utils/appfest_gen -out lucet_design_fig_17_A.json -physical_ports 1 \
%% -ofp_ports 2 -virtual_hosts 1 -physical_hosts 2
-define(JSON_FILE, "../lucet_design_fig_17_A.json").

%% Tests based on the topology shown in the figure 17A in the Lucet Desgin
%% document:
%% https://docs.google.com/document/d/1Gtoi8IX1EN3oWDRPTFa_VltOdJAwRbl_ChAZWk8oKIk/edit#
ld_fig17a_test_() ->
    {foreach, fun setup_dobby/0, fun(_) -> ok end,
     [fun it_finds_the_shortest_path_between_ep_and_ofp/0]}.

%% Tests

it_finds_the_shortest_path_between_ep_and_ofp() ->
    ok.

%% Internal functions

setup_dobby() ->
    application:stop(dobby),
    {ok, _} = application:ensure_all_started(dobby),
    ok = dby_mnesia:clear(),
    ok = dby_bulk:import(json, ?JSON_FILE).
