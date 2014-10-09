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

-module(sys_SUITE).
-compile(export_all).
-compile({no_auto_import, [statistics/1]}).

-import(cowboy_test, [config/2]).
-import(cowboy_test, [doc/1]).
-import(cowboy_test, [gun_open/1]).

%% ct.

all() ->
	cowboy_test:common_all().

groups() ->
	cowboy_test:common_groups(cowboy_test:all(?MODULE)).

init_per_group(Name, Config) ->
	cowboy_test:init_common_groups(Name, Config, ?MODULE).

end_per_group(Name, _) ->
	cowboy:stop_listener(Name).

%% Dispatch configuration.

init_dispatch(_) ->
	cowboy_router:compile([
		{'_', [
			{"/hibernate", system_h, {system_sp, hibernate}},
			{"/", system_h, {system_sp, run}}
		]}
	]).

%% Tests.

suspend_resume(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:suspend/1 and sys:resume/1"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	ok = sys:suspend(Pid),
	ok = sys:resume(Pid),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

hibernate_suspend_resume(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:suspend/1 and sys:resume/1 after hibernation"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/hibernate"),
	ok = sys:suspend(Pid),
	ok = sys:resume(Pid),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

get_state(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:get_state/1"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	{system_sp, Req, state} = sys:get_state(Pid),
	[{_, _} | _] = cowboy_req:to_list(Req),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

sys_replace_state(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:replace_state/2"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	Replace = fun({system_sp, Req, state}) ->
		Req2 = cowboy_req:set_meta(replaced, true, Req),
		{system_sp, Req2, new_state}
	end,
	{system_sp, Req3, new_state} = sys:replace_state(Pid, Replace),
	true = cowboy_req:meta(replaced, Req3, false),
	Get = fun(FullState) -> FullState end,
	{system_sp, Req3, new_state} = sys:replace_state(Pid, Get),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

bad_sys_replace_state(Config) ->
	doc("Ensure that a sub_protocol/middleware doesn't allow bad state replaces with sys:replace_state/2"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	Replace = fun({_, Req, state}) ->
		{new_module, Req, new_state}
	end,
	{'EXIT', {{callback_failed, _, _}, _}} = (catch sys:replace_state(Pid, Replace)),
	Replace2 = fun({Mod, _Req, State}) ->
			{Mod, not_req, State}
	end,
	{'EXIT', {{callback_failed, _, _}, _}} = (catch sys:replace_state(Pid, Replace2)),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

change_code(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:change_code/4"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	ok = sys:suspend(Pid),
	ok = sys:change_code(Pid, ?MODULE, undefined, undefined),
	ok = sys:resume(Pid),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

statistics(Config) ->
	doc("Ensure that a sub_protocol/middleware can handle sys:statistics/2"),
	ConnPid = gun_open(Config),
	{Pid, Ref} = system_gun_get(ConnPid, "/"),
	ok = sys:statistics(Pid, true),
	{ok, [{_,_} | _]} = sys:statistics(Pid, get),
	ok = sys:statistics(Pid, false),
	{ok, no_statistics} = sys:statistics(Pid, get),
	{response, fin, 204, _} = gun:await(ConnPid, Ref),
	ok.

%% Internal

system_gun_get(ConnPid, Path) ->
	Tag = make_ref(),
	QS = cow_qs:qs([{<<"from">>, term_to_binary({self(), Tag})}]),
	Ref = gun:get(ConnPid, [Path, $? | QS]),
	Pid = receive {Tag, P} -> P after 500 -> exit(timeout) end,
	{Pid, Ref}.
