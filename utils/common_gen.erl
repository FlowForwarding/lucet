-module(common_gen).

-define(TYPE(T), {<<"type">>, atom_to_binary(T, utf8)}).

-export([setup/0, publish/1, publish/2, publish/3, export_to_json/1,
         update_patchp_wires_md/1]).

-export([id_endpoint/1, id_lm_ph/1, id_lm_pp/1, id_lm_patchp/2, id_lm_vp/1,
         id_lm_vh/1, id_lm_of_port/1, id_lm_of_switch/1]).

-export([lk_bound_to_md/0, lk_part_of_md/0, lk_endpoint_md/0]).

%% API

setup() ->
    [os:cmd(io_lib:format("rm -rf ~p", [Dir]))
     || Dir <- filelib:wildcard("utils/Mnesia*"), filelib:is_dir(Dir)],
    code:add_pathsa(filelib:wildcard("deps/*/ebin")),
    {ok, _} = application:ensure_all_started(dobby),
    dby_mnesia:clear().


publish(Src, Dst, LinkMetadata) ->
    dby:publish(<<"lucet">>, Src, Dst, LinkMetadata, [persistent]).

publish(Endpoint) ->
    dby:publish(<<"lucet">>, Endpoint, [persistent]).

publish(Endpoint, Metadata) ->
    dby:publish(<<"lucet">>, {Endpoint, Metadata}, [persistent]).

export_to_json(Filename) ->
    ok = dby_bulk:export(json, Filename).

update_patchp_wires_md(NewWires) ->
    fun(MdProplist) ->
            Wires = proplists:get_value(<<"wires">>, MdProplist),
            [{<<"wires">>, maps:merge(NewWires, Wires)}
             | proplists:delete(<<"wires">>, MdProplist)]
    end.

%% API: Identifiers

id_endpoint(Name) ->
    {Name, [?TYPE(endpoint)]}.

id_lm_ph(Name) ->
    {Name, [?TYPE(lm_ph)]}.

id_lm_pp(Name) ->
    {Name, [?TYPE(lm_pp)]}.

id_lm_patchp(Name, Wires) ->
    {Name, [?TYPE(lm_patchp), {<<"wires">>, Wires}]}.

id_lm_vp(Name) ->
    {Name, [?TYPE(lm_vp)]}.

id_lm_vh(Name) ->
    {Name, [?TYPE(lm_vh)]}.

id_lm_of_port(Name) ->
    %% The type should be 'lm_of_port' but for now weave and dobby_oflib
    %% operate just on 'of_port'
    {Name, [?TYPE(of_port)]}.

id_lm_of_switch(Name) ->
    %% The type should be 'lm_of_switch' but for now weave and dobby_oflib
    %% operate just on 'of_switch'
    {Name, [?TYPE(of_switch)]}.

%% API: Links

lk_bound_to_md() ->
    [?TYPE(bound_to)].

lk_part_of_md() ->
    [?TYPE(part_of)].

lk_endpoint_md() ->
    [].
