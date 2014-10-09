%% Copyright (c) 2014, James Fish <james@fishcakez.com>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
-module(cowboy_sys).

%% API.
-export([handle_msg/6]).

% System.
-export([system_continue/3]).
-export([system_get_state/1]).
-export([system_replace_state/2]).
-export([system_code_change/4]).
-export([system_terminate/4]).

-type state() :: {module(), cowboy_req:req() | undefined, any()}.
-type replace_state() :: fun((state()) -> state()).
-export_type([replace_state/0]).

-callback sys_continue(cowboy_req:req() | undefined, any())
	-> {ok, cowboy_req:req(), cowboy_middleware:env()}
	| {suspend, module(), atom(), [any()]}
	| {system, {pid(), any()}, any(), module(), cowboy_req:req(), any()}
	| {halt, cowboy_req:req()}.
-callback sys_get_state(cowboy_req:req() | undefined, any())
	-> {ok, cowboy_req:req() | undefined, module(), any()}
	| {module(), cowboy_req:req() | undefined, any()}.
-callback sys_replace_state(replace_state(), cowboy_req:req() | undefined,
		any())
	-> {ok, cowboy_req:req() | undefined, module(), any()}
	| {module(), cowboy_req:req() | undefined, any(), any()}.
-callback sys_terminate(pid(), cowboy_req:req(), any()) -> no_return().

%% API.

-spec handle_msg(any(), {pid(), any()}, pid(), module(),
        cowboy_req:req() | undefined, any())
    -> no_return().
handle_msg(Msg, From, Parent, Mod, Req, ModState) ->
	Dbg = case get('$dbg') of
			undefined -> [];
			Other -> Other
	end,
	sys:handle_system_msg(Msg, From, Parent, ?MODULE, Dbg,
	{Mod, Req, ModState}).

%% System.

-spec system_continue(pid(), [sys:dbg_opt()], state()) -> no_return().
system_continue(_Parent, Dbg, {Mod, Req, ModState}) ->
	 _ = put('$dbg', Dbg),
	continue(Mod, sys_continue, [Req, ModState]).

-spec system_get_state(state()) -> {ok, state()}.
system_get_state({Mod, Req, ModState}) ->
	case Mod:sys_get_state(Req, ModState) of
		% sys_get_state/2 must not change Req object as changes will be lost.
		{ok, Req, ModState2} ->
			{ok, {Mod, Req, ModState2}};
		{Callback, Req, CallbackState} when is_atom(Callback) ->
			{ok, {Callback, Req, CallbackState}}
	end.

-spec system_replace_state(replace_state(), state())
	-> {ok, {module(), cowboy_req:req() | undefined, any()}, state()}.
system_replace_state(Replace, {Mod, Req, ModState}) ->
	case Mod:sys_replace_state(Replace, Req, ModState) of
		{ok, undefined, ModState2} ->
			State = {Mod, undefined, ModState2},
			{ok, State, State};
		{ok, Req2, ModState2} ->
			% Check Req2 is valid.
			_ = cowboy_req:get(pid, Req2),
			State = {Mod, Req2, ModState2},
			{ok, State, State};
		{Callback, undefined, CallbackState, ModState2}
				when is_atom(Callback) ->
			{ok, {Callback, undefined, CallbackState},
				{Mod, undefined, ModState2}};
		{Callback, Req2, CallbackState, ModState2} when is_atom(Callback) ->
			% Check Req2 is valid.
			_ = cowboy_req:get(pid, Req2),
			{ok, {Callback, Req2, CallbackState}, {Mod, Req2, ModState2}}
	end.

-spec system_code_change(state(), module(), any(), any()) -> {ok, state()}.
system_code_change(State, _Module, _OldVsn, _Extra) ->
	{ok, State}.

-spec system_terminate(any(), pid(), [sys:dbg_opt()], state()) -> no_return().
system_terminate(Reason, _Parent, Dbg, {Mod, Req, ModState}) ->
	_ = put('$dbg', Dbg),
	continue(Mod, sys_terminate, [Reason, Req, ModState]).

%% Internal.

continue(Module, Fun, Args) ->
	case process_info(self(), catchlevel) of
		% Process was hibernated while handling system messages and lost
		% cowboy_proc try..catch.
		{catchlevel, 1} ->
			cowboy_proc:continue(Module, Fun, Args);
		{catchlevel, 2} ->
			apply(Module, Fun, Args)
	end.
