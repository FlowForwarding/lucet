.PHONY: test compile run deps

deps:
	./rebar get-deps

compile: deps
	./rebar compile

test:
	./rebar eunit skip_deps=true

run: compile
	erl -pa ebin -pa deps/*/ebin \
	-eval "[application:ensure_all_started(A) || A <- [dobby, lucet]]"
	-eval "dby_bulk:import(json, $(topo))"
