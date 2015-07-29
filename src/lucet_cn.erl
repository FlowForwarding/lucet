-module(lucet_cn).

-export([import_cen_to_dobby/1]).

-spec import_cen_to_dobby(filename:filename_all()) -> ok | {error, Reason} when
      Reason :: term().

import_cen_to_dobby(Filename) ->
    {ok, Binary} = file:read_file(Filename),
    #{<<"cenList">> := Cens} = jiffy:decode(Binary, [return_maps]),
    ProcessedCens = process_cens(Cens),
    publsh_cens(ProcessedCens).

%% Internal functions

process_cens(CensMap) ->
    lists:foldl(fun process_cen/2, {[], sets:new(), []}, CensMap).

process_cen(#{<<"cenID">> := CenId, <<"containerIDs">> := ContainerIds},
           {CenIds, ContainerIdsSet, CenLinks}) ->
    {[CenId | CenIds],
     sets:union(ContainerIdsSet, sets:from_list(ContainerIds)),
     [{CenId, C} || C <- ContainerIds] ++ CenLinks};
process_cen(_, _) ->
    throw(bad_json).

publsh_cens({CenIds, ContainerIds, CenLinks}) ->
    ToPublish = [lucet_dby:cen_ep(C) || C <-CenIds]
        ++ [lucet_dby:cen_container_ep(C) || C <- sets:to_list(ContainerIds)]
        ++ [lucet_dby:cen_to_container_link(L) || L <- CenLinks],
    lucet_dby:publish(<<"lucet_cn">>, ToPublish).
