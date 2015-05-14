# lucet #

Wiring Compiler

## Generating JSON file for fig 14 A in Lucet Design ##

Lucet design: https://docs.google.com/document/d/1Gtoi8IX1EN3oWDRPTFa_VltOdJAwRbl_ChAZWk8oKIk/edit#heading=h.t814rryc9eo

`utils/ld_fig14a_json_gen topo.json`

## Generating JSON file for fig 17 A in Lucet Design ##

https://docs.google.com/document/d/1Gtoi8IX1EN3oWDRPTFa_VltOdJAwRbl_ChAZWk8oKIk/edit#heading=h.36uiclvajkxf

`./utils/appfest_gen -out appfest.json -physical_ports 10 -physical_hosts 4 -ofp_ports 4 -virtual_hosts 1`

The defaults values are:

```erlang
{out, "output.json"}, %% JSON output filename
{physical_hosts, 2}, %% physical hosts
{physical_ports, 4}, %% physical ports per ph
{ofp_ports, 4}, %% OpenFlow ports per vh with LNICX
{virtual_hosts, 1} %% virtual hosts per ph apart from vh with LINCX
```
