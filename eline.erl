#!/usr/bin/escript
-define(RED, "8F5B00").
-define(ORANGE, "FFCC00").
-define(GREEN, "66FF00").
-define(BLUE, "9933CC").

-record(stat, {
	fn,
	refresh = 1,
	error = ignore
}).

-record(state, {
	tick = 0,
	stat_servers = [],
	dict = []
}).

main(_) ->
	io:format("{\"version\":1}~n"),
	io:format("[~n[{\"full_text\": \"Loading...\"}]"),
	inets:start(),
	ssl:start(),
	update(#state{}).

stat_server(Super, R) ->
	F = R#stat.fn,
	Super !
		{
			self(),
			try F() of
				Res -> Res
			catch
				_A:_B -> R#stat.error
			end
		},
	timer:sleep(R#stat.refresh * 1000),
	stat_server(Super, R).	

spawn_all(Super) ->
	lists:map(
		fun(X) ->
			spawn(fun() -> stat_server(Super, X) end)
		end,
		lists:reverse(stats())
	).

update(S) when S#state.tick == 0 ->
	Servers = spawn_all(self()),
	update(
		S#state{
			stat_servers = Servers,
			dict = [ {PID, "Loading..."} || PID <- Servers ],
			tick = 1
		}
	);
update(S) ->
	receive
		{PID, Res} ->
			update(
				S#state {
					dict = lists:keyreplace(PID, 1, S#state.dict, {PID, Res}),
					tick = S#state.tick + 1
				}
			)
	after 300 ->
		X =
			lists:flatten(
				string:join(
					lists:map(
						fun({_,R}) when is_list(R) ->
							"{\"full_text\": \"" ++ R ++ "\"}";
						({_,{normal, R}}) ->
							"{\"full_text\": \"" ++ R ++ "\"}";
						({_,{C,R}}) ->
							"{\"color\": \"#" ++ C ++ "\", \"full_text\": \"" ++ R ++ "\"}"
						end,
						lists:filter(
							fun({_, ignore}) -> false;
							(_) -> true									
							end,
							S#state.dict
						)
					),
					",\n"
				)
			),
		io:format(",[~s]~n~n", [X]),
		update(S#state{tick=S#state.tick+1})
	end.

stats() ->
	[
		#stat{
			fn = 
				fun() -> 
					{{Yr, Mo, Da}, {Hr, Mi, Se}} = erlang:localtime(),
					{
						case Hr of
							X when X < 7 -> ?RED;
							X when X < 15 -> ?GREEN;
							X when X < 19 -> ?BLUE;
							X when X < 23 -> ?ORANGE;
							_ -> ?RED
						end,
						io_lib:format("~p/~p/~p ~2..0B:~2..0B:~2..0B", [Da, Mo, Yr, Hr, Mi, Se])
					}
				end
		},
		#stat{
			fn = 
				fun() ->
					{match, [M]} = re:run(os:cmd("cat /proc/uptime"), "(^[0-9]+).", [{capture, all_but_first, list}]),
					Sec = list_to_integer(M),
					Hr = Sec div 3600,
					Min = (Sec rem 3600) div 60,
					RM = integer_to_list(Min),
					{
						case Hr of
							0 -> ?BLUE;
							X when X < 4 -> ?GREEN;
							X when X < 12 -> ?ORANGE;
							_ -> ?RED
						end,
						"Uptime: " ++ integer_to_list(Hr) ++ ":" ++ case length(RM) of 1 -> "0" ++ RM; _ -> RM end
					}
				end,
			refresh = 60
		},
		#stat{
			fn =
				fun() ->
					{match, [M]} = re:run(os:cmd("sensors"), "([0-9]+)\\\.[0-9]{1}", [{capture, all_but_first, list}]),
					{
						case list_to_integer(hd(string:tokens(M, "."))) of
							X when X < 45 -> ?BLUE;
							X when X < 55 -> ?GREEN;
							X when X < 70 -> ?ORANGE;
							_ -> ?RED
						end,
						"Core: " ++ M ++ "°C"
					}
				end
		},
		#stat{
			fn = 
				fun() ->
					{match, [M]} = re:run(os:cmd("uptime"), "[0-9]\\.[0-9]{2}", [{capture, first, list}]),
					{
						case list_to_float(M) of
							X when X < 0.25 -> ?BLUE;
							X when X < 0.5 -> ?GREEN;
							X when X < 0.75 -> ?ORANGE;
							_ -> ?RED
						end,
						"Load: " ++ M
					}
				end
		},
		#stat{
			fn = 
				fun() ->
					{ok, {{_, 200, _}, _, Body}} = httpc:request("http://api.exip.org/?call=ip"),
					"IP: " ++ Body
				end,
			refresh = 60
		},
		#stat{
			fn = 
				fun() ->
					Ifs = ["enp2s0f0", "wlp3s0"],
					Parent = self(),
					lists:map(
						fun(If) ->
							{match, [Res, MK]} =
								re:run(
									os:cmd("vnstat -tr 5 -i " ++ If ++ " -ru"),
									"([0-9]+\.[0-9]{2}) (.)iB/s",
									[{capture, all_but_first, list}]
								),
							Parent ! {reading, If, {Res, if MK == "M" -> "MB"; true -> "KB" end}}
						end,
						Ifs
					),
					case
						lists:filter(
							fun({_, {[$0, $., _, $0], _}}) -> false;
							({_, {"0.20", _}}) -> false;
							(_) -> true
							end,
							lists:map(
								fun(_) ->
									receive
										{reading, If, Res} -> {If, Res}
									end
								end,
								Ifs
							)
						)
					of
						[] -> ignore;
						L ->
							Rx = list_to_float(StrRx = element(1, element(2, hd(L)))),
							{
								if Rx > 1500 -> ?GREEN;
								Rx > 500 -> ?ORANGE;
								true -> ?RED
								end,
								StrRx ++ " " ++ element(2, element(2, hd(L))) ++ " ↓"
							}
						end
				end,
			refresh = 3
		},
%		#stat{
%			fn =
%				fun() ->
%					{match, C} = re:run(os:cmd("ps aux | grep ssh"), "ssh", [global]),
%					{
%						case length(C)-2 of
%							0 -> ?BLUE;
%							1 -> ?GREEN;
%							2 -> ?ORANGE;
%							_ -> ?RED
%						end,
%						"Outbound SSH: " ++ integer_to_list(length(C)-1)
%					}
%				end,
%			refresh = 10
%		},
		#stat{
			fn = 
				fun() ->
					case re:run(os:cmd("nmcli -t -f name c status"), "VPN-CONNECTION-NAME") of
						nomatch -> ignore;
						_ -> {?GREEN, "VPN Enabled"}
					end
				end,
			refresh = 10
		},
		#stat{
			fn =
				fun() ->
					Num = try
						{ok, {_, _, Body}} =
							httpc:request(get, {"https://mail.google.com/mail/feed/atom",
								[
									{"Authorization", "Basic "
										++ base64:encode_to_string(
											lists:map(
												fun(X) -> X bxor 10 end,
												"*****************************"
											)
										)
									}
								]}, [], []),
						{match, [Res]} = re:run(Body, "<fullcount>([0-9]+)</fullcount>", [{capture, all_but_first, list}]),
						list_to_integer(Res)
					catch
						_A:_B -> "U"
					end,
					case Num of
						0 -> ignore;
						"U" -> ignore;
						X when is_integer(X) ->
							{
								case X of
									0 -> ?GREEN;
									Y when Y < 3 -> ?ORANGE;
									3 -> ?RED
								end,
								"Unread: " ++ integer_to_list(X)
							}
					end
				end,
			refresh = 60
		},
		#stat{
			fn =
				fun() ->
					try
						{ok, {_, _, Body}} = httpc:request("https://btc-e.com/api/2/ltc_usd/ticker"),
						{match, Res} =
							re:run(Body, "\"avg\": *([0-9]+\.{0,1}[0-9]*),.*\"last\": *([0-9]+\.{0,1}[0-9]*),", [{capture, all_but_first, list}]),
							[Avg, Last] =
								lists:map(
									fun(X) ->
										try list_to_float(X)
										catch error:badarg -> list_to_float(X ++ ".0")
										end
									end,
									Res
								),
							{
								if Last > Avg -> ?GREEN;
								Last < Avg -> ?RED;
								true -> ?ORANGE
								end,
								lists:flatten(io_lib:format("LTC: ~p", [Last]))
							}
					catch
				            _A:_B -> ignore
					end
				end,
			refresh = 30
		},
		#stat{
			fn = 
				fun() ->
					CMD = os:cmd("mpc"),
					Res =
						case length(string:tokens(CMD, [10])) of
							1 -> not_playing;
							_ -> string:substr(hd(string:tokens(CMD, [10])), 1, 55)
						end,
					{
						 case Res of not_playing -> ?RED; _ -> ?BLUE end,
						 "MPD: " ++ case Res of not_playing -> "Not Playing"; _ -> Res end
					}
				end,
			refresh = 5
		}
	].
