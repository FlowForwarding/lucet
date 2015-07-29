-module(lucet_dby).

-export([publish/2]).

-export([cen_ep/1,
         cen_container_ep/1,
         cen_to_container_link/1]).

publish(Who, Stuff) ->
    dby:publish(Who, Stuff, [persistent]).

cen_ep(CenId) when is_binary(CenId) ->
    {CenId, [{<<"type">>, <<"cen">>}]}.

cen_container_ep(ContainerId) when is_binary(ContainerId) ->
    {ContainerId, [{<<"type">>, <<"container">>}]}.

cen_to_container_link({CenId, ContainerId}) ->
    {CenId, ContainerId, [{<<"type">>, <<"cen_to_container">>}]}.
