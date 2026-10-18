-module(file_io_test_ffi).
-export([unique_id/0]).

%% Returns an integer that is unique within this VM and, thanks to the
%% wall-clock component, practically unique across test runs too.
unique_id() ->
    Time = erlang:system_time(microsecond),
    Counter = erlang:unique_integer([positive, monotonic]),
    Time * 1000000 + Counter.
