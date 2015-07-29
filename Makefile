.PHONY: test compile run deps

cookie ?= dobby

compile: deps
	./rebar compile

deps:
	./rebar get-deps

run: compile
	erl -pa ebin -pa deps/*/ebin \
	-name lucet@127.0.0.1 \
	-setcookie ${cookie} \
	-config sys.config \
	-eval "{ok, _} = application:ensure_all_started(lucet)" \
	-eval "lucet_utils:connect_to_dobby()"

test:
	./rebar eunit skip_deps=true

