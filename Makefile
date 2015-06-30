.PHONY: test compile run deps

compile: deps
	./rebar compile

deps:
	./rebar get-deps

test:
	./rebar eunit skip_deps=true

run: compile
	erl -pa ebin -pa deps/*/ebin \
	-eval "[application:ensure_all_started(A) || A <- [dobby, lucet]]"
	-eval "dby_bulk:import(json, $(topo))"

# Connect to a Dobby node running on the local host
connect: compile
	erl -pa ebin -pa deps/*/ebin \
	    -name lucet@127.0.0.1 \
	    -setcookie dobby \
	    -eval "pong =:= net_adm:ping('dobby@127.0.0.1') orelse begin io:format(standard_error, \"\nCannot connect to Dobby node; exiting\n\", []), halt(1) end" \
	    -eval "{ok, _} = application:ensure_all_started(lucet)"
