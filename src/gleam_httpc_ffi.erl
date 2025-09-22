-module(gleam_httpc_ffi).
-export([default_user_agent/0, normalise_error/1, stream_next/1, coerce_stream_message/1]).

%%====================================================================
%% Streaming
%%====================================================================
 %% Helper: call stream_next with whatever the handler expects
stream_next(HandlerPid) when is_pid(HandlerPid) ->
 case httpc:stream_next(HandlerPid) of
   ok -> {ok, nil};
   _  -> {error, nil}
 end.

coerce_stream_message({http, {ReqId, stream_start, Headers, Pid}}) -> {stream_start, ReqId, Headers, Pid};
coerce_stream_message({http, {ReqId, stream, BinBodyPart}}) -> {stream_chunk, ReqId, BinBodyPart};
coerce_stream_message({http, {ReqId, stream_end, Headers}}) -> {stream_end, ReqId, Headers};
coerce_stream_message({http, {ReqId, {error, Reason}}}) -> {stream_error, ReqId, normalise_error(Reason)}. 
  
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
