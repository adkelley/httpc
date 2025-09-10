-module(gleam_httpc_ffi).
-export([default_user_agent/0, normalise_error/1, stream_next/1, 'receive'/2]).
%% -export([default_user_agent/0, normalise_error/1, stream_next/1, 'receive'/2, stream_to_file/0]).

%% stream_to_file() ->
%%     Url = "https://postman-echo.com/stream/5",
%%     Filename = tmpfile("httpc_stream_test"),
%%     %% Asynchronous request; body streamed to file by httpc
%%     {ok, ReqId} =
%%         httpc:request(
%%           get,
%%           {Url, []},
%%           [],  %% HTTP options
%%           [{sync, false}, {stream, Filename}]  %% client options
%%         ).

%% tmpfile(Prefix) ->
%%     Dir = case os:getenv("TMPDIR") of false -> "/tmp"; D -> D end,
%%     Name = io_lib:format("~s~p.bin", [Prefix, erlang:unique_integer([monotonic, positive])]),
%%     filename:join(Dir, lists:flatten(Name)).
%%====================================================================
%% Streaming
%%====================================================================
 %% Helper: call stream_next with whatever the handler expects
stream_next(HandlerPid) when is_pid(HandlerPid) ->
 case httpc:stream_next(HandlerPid) of
   ok -> {ok, nil};
   _  -> {error, nil}
 end.

'receive'(ReqId, Timeout) ->
   receive
     {http, {ReqId, stream_start, Headers}} -> {ok, {stream_start, Headers}};
     {http, {ReqId, stream_start, Headers, Pid}} -> {ok, {stream_start, {Headers, Pid}}};
     {http, {ReqId, stream, Chunk}} -> {ok, {stream, Chunk}};
     {http, {ReqId, stream_end, EndInfo}} -> {ok, {stream_end, EndInfo}};
     {http, {ReqId, saved_to_file}} -> {ok, {saved_to_file, nil}};
     {http, {ReqId, {{Version, Status, Reason}, Headers, Body}}} -> {ok, {stream_none, {{Version, Status, Reason}, Headers, Body}}};
     {http, {ReqId, {error, Reason}}} -> {error, Reason}
   after Timeout ->
     {error, timeout}
   end.
    

%%====================================================================
%% Error normalization
%%====================================================================

normalise_error(Error = {failed_connect, Opts}) ->
    Ipv6 = case lists:keyfind(inet6, 1, Opts) of
        {inet6, _, V1} -> V1;
        _ -> erlang:error({unexpected_httpc_error, Error})
    end,
    Ipv4 = case lists:keyfind(inet, 1, Opts) of
        {inet, _, V2} -> V2;
        _ -> erlang:error({unexpected_httpc_error, Error})
    end,
    {failed_to_connect, normalise_ip_error(Ipv4), normalise_ip_error(Ipv6)};
normalise_error(timeout) -> 
    response_timeout;
normalise_error(Error) ->
    erlang:error({unexpected_httpc_error, Error}).

normalise_ip_error(Code) when is_atom(Code) ->
    {posix, erlang:atom_to_binary(Code)};
normalise_ip_error({tls_alert, {A, B}}) ->
    {tls_alert, erlang:atom_to_binary(A), unicode:characters_to_binary(B)};
normalise_ip_error(Error) ->
    erlang:error({unexpected_httpc_ip_error, Error}).

default_user_agent() ->
    Version =
        case application:get_key(gleam_httpc, vsn) of
            {ok, V} when is_list(V) -> V;
            undefined -> "0.0.0"
        end,
    {"user-agent", "gleam_httpc/" ++ Version}.
