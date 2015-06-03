-module(lucet_topo_utils).

-export([daisychain_connections/3,
         endpoint_connections/3]).

%% @doc Returns a list of tuples with identifiers to connect to get
%% dayisy chain topolgy.
%%
%% `PhCnt' idnicates the number of Physical Hosts that are to be to
%% daisychained. `OfpANo' stands for LINCX port number on PH_X that is
%% to be connected to `OfpBNo' on PH_X+1.
daisychain_connections(PhCnt, OfpANo, OfpBNo) ->
    [begin
         PhA = "PH" ++ integer_to_list((No rem PhCnt) + 1),
         PhB = "PH" ++ integer_to_list(((No + 1) rem PhCnt) + 1),
         OfpA = "OFP" ++ integer_to_list(OfpANo),
         OfpB = "OFP" ++ integer_to_list(OfpBNo),
         {list_to_binary(string:join([PhA, "VH1", "OFS1", OfpA], "/")),
          list_to_binary(string:join([PhB, "VH1", "OFS1", OfpB], "/"))}
     end || No <- lists:seq(0, PhCnt - 1)].


endpoint_connections(Ph, FirstOfp, VMsCnt) ->
    [begin
         OFP = list_to_binary(string:join([Ph, "VH1", "OFS1",
                                           "OFP" ++ integer_to_list(FirstOfp + No)],
                                          "/")),
         %% VM run on vh starting from VH2
         VmVh = "VH" ++ integer_to_list(No + 2),
         EP = list_to_binary(string:join([Ph, VmVh, "EP1"], "/")),
         {OFP, EP}
     end || No <- lists:seq(0, VMsCnt - 1)].
