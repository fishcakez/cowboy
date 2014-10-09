-module(system_sp).

-export([upgrade/6]).
-export([loop/3]).
-export([sys_continue/2]).
-export([sys_get_state/2]).
-export([sys_replace_state/3]).
-export([sys_terminate/3]).

upgrade(Req, Env, _, State, _, run) ->
	loop(Req, Env, State);
upgrade(Req, Env, _, State, _, hibernate) ->
	{suspend, ?MODULE, loop, [Req, Env, State]}.

loop(Req, Env, State) ->
	receive
		{system, From, Msg} ->
			{system, From, Msg, ?MODULE, Req, {Env, State}}
	after 500 ->
		{ok, Req, [{result, ok} | Env]}
	end.

sys_continue(Req, {Env, State}) ->
	loop(Req, Env, State).

sys_get_state(Req, {_Env, State}) ->
	{ok, Req, State}.

sys_replace_state(Replace, Req, {_Env, State}) ->
	{?MODULE, Req2, State2} = Replace({?MODULE, Req, State}),
	{?MODULE, Req2, State2, {_Env, State2}}.

sys_terminate(Reason, _Req, {_Env, _State}) ->
	exit(Reason).
