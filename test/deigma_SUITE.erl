%% Copyright (c) 2018 Guilherme Andrade
%%
%% Permission is hereby granted, free of charge, to any person obtaining a
%% copy  of this software and associated documentation files (the "Software"),
%% to deal in the Software without restriction, including without limitation
%% the rights to use, copy, modify, merge, publish, distribute, sublicense,
%% and/or sell copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO WORK SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
%% DEALINGS IN THE SOFTWARE.

-module(deigma_SUITE).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

-ifdef(RUNNING_ON_TRAVIS).
-define(ASK_TEST_DURATION, (timer:seconds(3))).
-else.
-define(ASK_TEST_DURATION, (timer:seconds(1))).
-endif.

-ifdef(POST_OTP17).
-define(WINDOW_TIME_SPAN, (erlang:convert_time_unit(1, seconds, native))).
-else.
% dirty hack so we don't have to share macros and internal code with the event window
-define(WINDOW_TIME_SPAN, (1000000)).
-endif.

%% ------------------------------------------------------------------
%% Enumeration
%% ------------------------------------------------------------------

all() ->
    [{group, GroupName} || {GroupName, _Options, _TestCases} <- groups()].

groups() ->
    GroupNames = [individual_tests],
    [{GroupName, [parallel], individual_test_cases()} || GroupName <- GroupNames].

individual_test_cases() ->
    ModuleInfo = ?MODULE:module_info(),
    {exports, Exports} = lists:keyfind(exports, 1, ModuleInfo),
    [Name || {Name, 1} <- Exports, lists:suffix("_test", atom_to_list(Name))].

%% ------------------------------------------------------------------
%% Initialization
%% ------------------------------------------------------------------

init_per_testcase(_TestCase, Config) ->
    {ok, _} = application:ensure_all_started(sasl),
    {ok, _} = application:ensure_all_started(deigma),
    Config.

end_per_testcase(_TestCase, Config) ->
    Config.

%% ------------------------------------------------------------------
%% Definition
%% ------------------------------------------------------------------

ask_10_1_test(Config) ->
    run_ask_test(10, 1),
    Config.

ask_100_1_test(Config) ->
    run_ask_test(100, 1),
    Config.

ask_1000_1_test(Config) ->
    run_ask_test(1000, 1),
    Config.

ask_10_10_test(Config) ->
    run_ask_test(10, 10),
    Config.

ask_100_10_test(Config) ->
    run_ask_test(100, 10),
    Config.

ask_1000_10_test(Config) ->
    run_ask_test(1000, 10),
    Config.

ask_10_100_test(Config) ->
    run_ask_test(10, 100),
    Config.

ask_100_100_test(Config) ->
    run_ask_test(100, 100),
    Config.

ask_1000_100_test(Config) ->
    run_ask_test(1000, 100),
    Config.

ask_10_1000_test(Config) ->
    run_ask_test(10, 1000),
    Config.

ask_100_1000_test(Config) ->
    run_ask_test(100, 1000),
    Config.

ask_1000_1000_test(Config) ->
    run_ask_test(1000, 1000),
    Config.

default_event_fun_test(_Config) ->
    {ok, _Pid} = deigma:start(default_event_fun_test),
    ?assertEqual({accept,1.0}, deigma:ask(default_event_fun_test, foobar)),
    ?assertEqual({accept,1.0}, deigma:ask(default_event_fun_test, foobar, [])),
    ?assertEqual({accept,1.0}, deigma:ask(default_event_fun_test, foobar, [{max_rate,5000}])),
    ok = deigma:stop(default_event_fun_test),
    {error, not_started} = deigma:stop(default_event_fun_test).

custom_event_fun_test(_Config) ->
    {ok, _Pid} = deigma:start(custom_event_fun_test),
    Ref = make_ref(),
    ?assertEqual(yes,    deigma:ask(custom_event_fun_test, foobar, event_fun({value, yes}))),
    ?assertEqual(no,     deigma:ask(custom_event_fun_test, foobar, event_fun({value, no}))),
    ?assertEqual(self(), deigma:ask(custom_event_fun_test, foobar, event_fun({value, self()}))),
    ?assertEqual(Ref,    deigma:ask(custom_event_fun_test, foobar, event_fun({value, Ref}))),
    ok = deigma:stop(custom_event_fun_test).

crashing_event_fun_test(_Config) ->
    {ok, _Pid} = deigma:start(crashing_event_fun_test),
    ?assertMatch(yes,
                 catch deigma:ask(crashing_event_fun_test, foobar, event_fun({exception, throw, yes}))),
    ?assertMatch(no,
                 catch deigma:ask(crashing_event_fun_test, foobar, event_fun({exception, throw, no}))),
    ?assertMatch({'EXIT', {its_working, _}},
                 catch deigma:ask(crashing_event_fun_test, foobar, event_fun({exception, error, its_working}))),
    ?assertMatch({'EXIT', oh_my},
                 catch deigma:ask(crashing_event_fun_test, foobar, event_fun({exception, exit, oh_my}))),
    ok = deigma:stop(crashing_event_fun_test).

%% ------------------------------------------------------------------
%% Internal
%% ------------------------------------------------------------------

run_ask_test(NrOfEventTypes, MaxRate) ->
    Category =
        list_to_atom(
          "ask_" ++
          integer_to_list(NrOfEventTypes) ++
          "_" ++
          integer_to_list(MaxRate) ++
          "_test"),
    {ok, _Pid} = deigma:start(Category),
    _ = erlang:send_after(5000, self(), test_over),
    run_ask_test_recur(Category, NrOfEventTypes, MaxRate, []),
    ok = deigma:stop(Category).

run_ask_test_recur(Category, NrOfEventTypes, MaxRate, Acc) ->
    Timeout = rand_uniform(2) - 1,
    receive
        test_over ->
            check_ask_test_results(MaxRate, Acc)
    after
        Timeout ->
            EventType = rand_uniform(NrOfEventTypes),
            {Ts, Decision, SampleRate} =
                deigma:ask(
                  Category, EventType,
                  fun (Ts, Decision, SampleRate) ->
                          {Ts, Decision, SampleRate}
                  end,
                  [{max_rate, MaxRate}]),
            UpdatedAcc = [{Ts, EventType, Decision, SampleRate} | Acc],
            run_ask_test_recur(Category, NrOfEventTypes, MaxRate, UpdatedAcc)
    end.

check_ask_test_results(MaxRate, Results) ->
    ResultsPerEventType =
        lists:foldl(
          fun ({Ts, EventType, Decision, SampleRate}, Acc) ->
                  maps_update_with(
                    EventType,
                    fun (Events) -> [{Ts, Decision, SampleRate} | Events] end,
                    [{Ts, Decision, SampleRate}],
                    Acc)
          end,
          #{}, Results),

    lists:foreach(
      fun ({_EventType, Events}) ->
              check_ask_test_decisions(MaxRate, Events),
              check_ask_test_rates(Events)
      end,
      lists:keysort(1, maps:to_list(ResultsPerEventType))).

check_ask_test_decisions(MaxRate, Events) ->
    check_ask_test_decisions(MaxRate, Events, [], 0, 0).

check_ask_test_decisions(_MaxRate, [], _Acc, RightDecisions, WrongDecisions) ->
    ct:pal("RightDecisions ~p, WrongDecisions ~p", [RightDecisions, WrongDecisions]),
    ?assert(WrongDecisions / (RightDecisions + WrongDecisions) < 0.01);
check_ask_test_decisions(MaxRate, [Event | Next], Prev, RightDecisions, WrongDecisions) ->
    {Ts, Decision, _SampleRate} = Event,
    RelevantPrev = relevant_history(Ts, Prev),
    CountPerDecision = count_history_decisions(RelevantPrev),
    PrevAcceptances = maps:get(accept, CountPerDecision),
    RightDecision =
        case PrevAcceptances >= MaxRate of
            true -> drop;
            false -> accept
        end,

    case RightDecision =:= Decision of
        false ->
            check_ask_test_decisions(MaxRate, Next, [Event | RelevantPrev],
                                     RightDecisions, WrongDecisions + 1);
        true ->
            check_ask_test_decisions(MaxRate, Next, [Event | RelevantPrev],
                                     RightDecisions + 1, WrongDecisions)
    end.

relevant_history(Ts, Prev) ->
    TsFloor = Ts - ?WINDOW_TIME_SPAN,
    lists:takewhile(
      fun ({EntryTs, _Decision, _SampleRate}) ->
              EntryTs >= TsFloor
      end,
      Prev).

count_history_decisions(Prev) ->
    lists:foldl(
      fun ({_Ts, Decision, _SampleRate}, Acc) ->
              maps_update_with(
                Decision,
                fun (Val) -> Val + 1 end,
                Acc)
      end,
      maps:from_list(
        % We declare the map as this rather than a literal
        % because of a weird bug in OTP 17.
        [{accept, 0},
         {drop, 0}
        ]),
      Prev).

check_ask_test_rates(Events) ->
    check_ask_test_rates(Events, []).

check_ask_test_rates([], _Prev) ->
    ok;
check_ask_test_rates([Event | Next], Prev) ->
    {Ts, Decision, SampleRate} = Event,
    ?assert(SampleRate >= 0 andalso SampleRate =< 1),
    RelevantPrev = relevant_history(Ts, Prev),
    CountPerDecision = count_history_decisions(RelevantPrev),
    PrevAcceptances = maps:get(accept, CountPerDecision),
    PrevDrops = maps:get(drop, CountPerDecision),
    ct:pal("PrevAcceptances ~p, PrevDrops ~p", [PrevAcceptances, PrevDrops]),
    Total = PrevAcceptances + PrevDrops + 1,
    RealSampleRate =
        if Decision =:= accept ->
               (PrevAcceptances + 1) / Total;
           Decision =:= drop ->
               (PrevAcceptances / Total)
        end,
    ?assertEqual(RealSampleRate, SampleRate),
    check_ask_test_rates(Next, [Event | Prev]).

event_fun({value, Value}) ->
    fun (_Timestamp, Decision, SampleRate) ->
            ?assert(lists:member(Decision, [accept, drop])),
            ?assert(SampleRate >= 0 andalso SampleRate =< 1),
            Value
    end;
event_fun({exception, Class, Reason}) ->
    fun (_Timestamp, Decision, SampleRate) ->
            ?assert(lists:member(Decision, [accept, drop])),
            ?assert(SampleRate >= 0 andalso SampleRate =< 1),
            erlang:raise(Class, Reason, [])
    end.

-ifdef(POST_OTP18).
maps_update_with(Key, Fun, Map) ->
    maps:update_with(Key, Fun, Map).

maps_update_with(Key, Fun, Init, Map) ->
    maps:update_with(Key, Fun, Init, Map).
-else.
maps_update_with(Key, Fun, Map) ->
    case maps:find(Key, Map) of
        {ok, Value} ->
            UpdatedValue = Fun(Value),
            maps:update(Key, UpdatedValue, Map)
    end.

maps_update_with(Key, Fun, Init, Map) ->
    case maps:find(Key, Map) of
        {ok, Value} ->
            UpdatedValue = Fun(Value),
            maps:update(Key, UpdatedValue, Map);
        error ->
            maps:put(Key, Init, Map)
    end.
-endif.

-ifdef(POST_OTP17).
rand_seed() ->
    ok.

rand_uniform(N) ->
    rand:uniform(N).
-else.
rand_seed() ->
    Now = erlang:now(),
    random:seed(Now).

rand_uniform(N) ->
    random:uniform(N).
-endif.
