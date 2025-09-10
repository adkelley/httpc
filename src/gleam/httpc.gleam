import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/list
import gleam/result
import gleam/uri

pub type HttpError {
  /// The response body contained non-UTF-8 data, but UTF-8 data was expected.
  InvalidUtf8Response
  /// It was not possible to connect to the host.
  FailedToConnect(ip4: ConnectError, ip6: ConnectError)
  /// The response was not received within the configured timeout period.
  ResponseTimeout
}

pub type ConnectError {
  Posix(code: String)
  TlsAlert(code: String, detail: String)
}

@external(erlang, "gleam_httpc_ffi", "default_user_agent")
fn default_user_agent() -> #(Charlist, Charlist)

@external(erlang, "gleam_httpc_ffi", "normalise_error")
fn normalise_error(error: Dynamic) -> HttpError

type ErlHttpOption {
  Ssl(List(ErlSslOption))
  Autoredirect(Bool)
  Timeout(Int)
}

type BodyFormat {
  Binary
}

type ErlOption {
  BodyFormat(BodyFormat)
  SocketOpts(List(SocketOpt))
  Sync(Bool)
  Stream(Dynamic)
}

/// Streaming Options
pub type Stream {
  /// Buffer and deliver response in one final message.
  /// This is the default streaming option
  StreamNone
  /// Deliver chunks to the calling process continuously.
  StreamSelf
  /// Deliver one chunk at a time to the calling process.
  /// You must explicitly call httpc/async_stream_next() to
  /// before receiving the next chunk.
  StreamSelfOnce
  /// Stream response body directly into a file.
  StreamFile(String)
}

/// Stream response body directly into an I/O device (like standard_io).
/// (Currently not supported)
type SocketOpt {
  Ipfamily(Inet6fb4)
}

type Inet6fb4 {
  Inet6fb4
}

type ErlSslOption {
  Verify(ErlVerifyOption)
}

type ErlVerifyOption {
  VerifyNone
}

@external(erlang, "httpc", "request")
fn erl_request(
  a: Method,
  b: #(Charlist, List(#(Charlist, Charlist)), Charlist, BitArray),
  c: List(ErlHttpOption),
  d: List(ErlOption),
) -> Result(
  #(#(Charlist, Int, Charlist), List(#(Charlist, Charlist)), BitArray),
  Dynamic,
)

@external(erlang, "httpc", "request")
fn erl_request_no_body(
  a: Method,
  b: #(Charlist, List(#(Charlist, Charlist))),
  c: List(ErlHttpOption),
  d: List(ErlOption),
) -> Result(
  #(#(Charlist, Int, Charlist), List(#(Charlist, Charlist)), BitArray),
  Dynamic,
)

@external(erlang, "httpc", "request")
fn erl_request_async_no_body(
  a: Method,
  b: #(Charlist, List(#(Charlist, Charlist))),
  c: List(ErlHttpOption),
  d: List(ErlOption),
) -> Result(Reference, Dynamic)

@external(erlang, "httpc", "request")
fn erl_request_async(
  a: Method,
  b: #(Charlist, List(#(Charlist, Charlist)), Charlist, BitArray),
  c: List(ErlHttpOption),
  d: List(ErlOption),
) -> Result(Reference, Dynamic)

fn string_header(header: #(Charlist, Charlist)) -> #(String, String) {
  let #(k, v) = header
  #(charlist.to_string(k), charlist.to_string(v))
}

// TODO: refine error type
/// Send a HTTP request of binary data using the default configuration.
///
/// If you wish to use some other configuration use `dispatch_bits` instead.
///
pub fn send_bits(
  req: Request(BitArray),
) -> Result(Response(BitArray), HttpError) {
  configure()
  |> dispatch_bits(req)
}

// region:    --- asynchronous HTTP request
// 

// Utilities for converting between Dynamic and Gleam Types
@external(erlang, "gleam_stdlib", "identity")
fn atom_tuple_to_dynamic(t: #(Atom, Atom)) -> Dynamic

@external(erlang, "gleam_stdlib", "identity")
fn charlist_to_dynamic(t: Charlist) -> Dynamic

/// When streaming to the calling process using `Stream(SelfOnce)`, the first
/// stream message that is returned by `httpc.async_receive` is the `Dynamic`
/// data `#(stream_start, #(headers, pid))` where `stream_start` is an `Atom`.
/// This convenience function converts `headers` and `pid` to a tuple, of
/// `List(#(Charlist, Charlist))` and `Pid` respectively for further
/// processing by the caller.
@external(erlang, "gleam_stdlib", "identity")
pub fn dynamic_to_headers_pid(s: Dynamic) -> #(List(#(Charlist, Charlist)), Pid)

/// When streaming to the calling process using `Stream(SelfOnce)`, the first
/// stream message that is returned by `httpc.async_receive` is the `Dynamic`
/// data `#(stream_start, headers)` This convenience function that converts
/// `headers` to `List(#(Charlist, Charlist))` for further processing by the caller.
@external(erlang, "gleam_stdlib", "identity")
pub fn dynamic_to_headers(s: Dynamic) -> List(#(Charlist, Charlist))

/// When streaming to the calling process using `Stream(SelfOnce)`, the second and
/// often multiple consecutive stream messages that is returned by `httpc.async_receive`
/// is the `Dynamic` data `#(stream, chunk)` This is a convenience function that converts
/// `chunk` to a `BitArray` for further processing by the caller.
@external(erlang, "gleam_stdlib", "identity")
pub fn dynamic_to_bit_array(s: Dynamic) -> BitArray

/// When streaming to the calling process using `Stream(None)`, the entire response
/// is delivered in one final message, `#(stream_none, #(#(version, status, reason), headers, body))`.
/// This is a convenience function that converts the `Dynamic` data represented by the second
/// element of this tuple to `#(#(Charlist, Int, Charlist), List(#(Charlist, Charlist)), BitArray)`
/// for further processing by the caller.
@external(erlang, "gleam_stdlib", "identity")
pub fn dynamic_to_response(
  s: Dynamic,
) -> #(#(Charlist, Int, Charlist), List(#(Charlist, Charlist)), BitArray)

@external(erlang, "gleam_httpc_ffi", "stream_next")
fn stream_next(pid: Pid) -> Result(Nil, Nil)

// TODO: refine error type
/// Send a asyncrhonous HTTP request of binary data
pub fn async_dispatch_bits(
  config: Configuration,
  req: Request(BitArray),
) -> Result(Reference, HttpError) {
  let erl_url =
    req
    |> request.to_uri
    |> uri.to_string
    |> charlist.from_string
  let erl_headers = prepare_headers(req.headers)
  let erl_http_options = [
    Autoredirect(config.follow_redirects),
    Timeout(config.timeout),
  ]
  let erl_http_options = case config.verify_tls {
    True -> erl_http_options
    False -> [Ssl([Verify(VerifyNone)]), ..erl_http_options]
  }
  let erl_options = [
    Sync(False),
    BodyFormat(Binary),
    SocketOpts([Ipfamily(Inet6fb4)]),
  ]
  let self = atom.create("self")
  let once = atom.create("once")
  let erl_options = case config.stream {
    StreamNone -> [Stream(atom.to_dynamic(atom.create("none"))), ..erl_options]
    StreamSelf -> [Stream(atom.to_dynamic(self)), ..erl_options]
    StreamSelfOnce -> [
      Stream(atom_tuple_to_dynamic(#(self, once))),
      ..erl_options
    ]
    StreamFile(filename) -> [
      Stream(charlist_to_dynamic(charlist.from_string(filename))),
      ..erl_options
    ]
  }

  use request_id <- result.try(
    case req.method {
      http.Options | http.Head | http.Get -> {
        let erl_req = #(erl_url, erl_headers)
        erl_request_async_no_body(
          req.method,
          erl_req,
          erl_http_options,
          erl_options,
        )
      }
      _ -> {
        let erl_content_type =
          req
          |> request.get_header("content-type")
          |> result.unwrap("application/octet-stream")
          |> charlist.from_string
        let erl_req = #(erl_url, erl_headers, erl_content_type, req.body)
        erl_request_async(req.method, erl_req, erl_http_options, erl_options)
      }
    }
    |> result.map_error(normalise_error),
  )

  Ok(request_id)
}

// Receive a message that has been sent the the current process using a
// `NamedSubject`. In this case the subject name is `http`
@external(erlang, "gleam_httpc_ffi", "receive")
fn receive(req_id: Reference, timeout: Int) -> Result(#(Atom, Dynamic), Atom)

/// Receive an ansynchronous stream message to the process designated by the
/// `request_id`.  For a description of those messages, see the documentation for
/// `httpc.async_stream`. The Dynamic data response may be decoded by the caller
/// using the convenience functions `httpc.dynamic_to_header_pid`,
/// `httpc.dynamic_to_header`, and `httpc.dynamic_to_bit_array`
/// TODO: Refine Error
pub fn async_receive(
  req_id: Reference,
  timeout: Int,
) -> Result(#(Atom, Dynamic), HttpError) {
  use response <- result.try(
    receive(req_id, timeout)
    |> result.map_error(with: fn(reason) {
      case atom.to_string(reason) {
        "timeout" -> ResponseTimeout
        _ -> InvalidUtf8Response
      }
    }),
  )
  Ok(response)
}

///  Call this function when using the `Stream` option `StreamOnce`
///  It triggers the next message to be sent to the calling process designated by
/// `pid`. 
pub fn async_stream_next(pid: Pid) -> Result(Nil, HttpError) {
  use _next <- result.try(
    // TODO return reason somehow? {http, {ReqId, {error, Reason}}}
    stream_next(pid) |> result.replace_error(InvalidUtf8Response),
  )
  Ok(Nil)
}

// endregion: --- asynchronous http request

// region:    --- synchronous http request

// TODO: refine error type
/// Send a HTTP request of binary data.
///
pub fn dispatch_bits(
  config: Configuration,
  req: Request(BitArray),
) -> Result(Response(BitArray), HttpError) {
  let erl_url =
    req
    |> request.to_uri
    |> uri.to_string
    |> charlist.from_string
  let erl_headers = prepare_headers(req.headers)
  let erl_http_options = [
    Autoredirect(config.follow_redirects),
    Timeout(config.timeout),
  ]
  let erl_http_options = case config.verify_tls {
    True -> erl_http_options
    False -> [Ssl([Verify(VerifyNone)]), ..erl_http_options]
  }
  let erl_options = [BodyFormat(Binary), SocketOpts([Ipfamily(Inet6fb4)])]

  use response <- result.try(
    case req.method {
      http.Options | http.Head | http.Get -> {
        let erl_req = #(erl_url, erl_headers)
        erl_request_no_body(req.method, erl_req, erl_http_options, erl_options)
      }
      _ -> {
        let erl_content_type =
          req
          |> request.get_header("content-type")
          |> result.unwrap("application/octet-stream")
          |> charlist.from_string
        let erl_req = #(erl_url, erl_headers, erl_content_type, req.body)
        erl_request(req.method, erl_req, erl_http_options, erl_options)
      }
    }
    |> result.map_error(normalise_error),
  )

  let #(#(_version, status, _status), headers, resp_body) = response

  Ok(Response(status, list.map(headers, string_header), resp_body))
}

// endregion: --- synchronous request

/// Configuration that can be used to send HTTP requests.
///
/// To be used with `dispatch` and `dispatch_bits`.
///
pub opaque type Configuration {
  Builder(
    /// Whether to verify the TLS certificate of the server.
    ///
    /// This defaults to `True`, meaning that the TLS certificate will be verified
    /// unless you call this function with `False`.
    ///
    /// Setting this to `False` can make your application vulnerable to
    /// man-in-the-middle attacks and other security risks. Do not do this unless
    /// you are sure and you understand the risks.
    ///
    verify_tls: Bool,
    /// Whether to follow redirects.
    ///
    follow_redirects: Bool,
    /// Timeout for the request in milliseconds.
    ///
    timeout: Int,
    /// Used to set the streaming options when streaming asynchronously to the
    /// calling process.
    /// 
    /// Default is `StreamNone`, which buffers and send the entire response
    /// in one final message.
    stream: Stream,
  )
}

/// Create a new configuration with the default settings.
///
/// # Defaults
///
/// - TLS is verified.
/// - Redirects are not followed.
/// - The timeout for the response to be received is 30 seconds from when the
///   request is sent.
/// - Requests are synchronous by default. However, when sending asychronous
///   HTTP requests, the default stream option is `StreamNone`, which buffers
///   and sends the entire response in one final message.
pub fn configure() -> Configuration {
  Builder(
    verify_tls: True,
    follow_redirects: False,
    timeout: 30_000,
    stream: StreamNone,
  )
}

/// Set whether to verify the TLS certificate of the server.
///
/// This defaults to `True`, meaning that the TLS certificate will be verified
/// unless you call this function with `False`.
///
/// Setting this to `False` can make your application vulnerable to
/// man-in-the-middle attacks and other security risks. Do not do this unless
/// you are sure and you understand the risks.
///
pub fn verify_tls(config: Configuration, which: Bool) -> Configuration {
  Builder(..config, verify_tls: which)
}

/// Set whether redirects should be followed automatically.
pub fn follow_redirects(config: Configuration, which: Bool) -> Configuration {
  Builder(..config, follow_redirects: which)
}

/// Set the timeout in milliseconds, the default being 30 seconds.
///
/// If the response is not recieved within this amount of time then the
/// client disconnects and an error is returned.
///
pub fn timeout(config: Configuration, timeout: Int) -> Configuration {
  Builder(..config, timeout:)
}

/// Set the type of asychronous(i.e, streaming) HTTP request.
/// 
/// When streaming to the calling process using the option `StreamSelf`, the following
/// stream messages are sent to that process: `#(http, #(RequestId, stream_start, Headers)`,
/// `#(http, #(RequestId, stream, BinBodyPart))`, and `#(http, (RequestId, stream_end, Headers))`.  
/// 
/// When streaming to the calling processes using option `StreamSelfOnce`, the first
/// message has an extra element, `Pid`.  That is, `#(http, #(RequestId, stream_start, Headers, Pid))`.
/// This is the process id to be used as an argument to `httpc.stream_next(pid: Pid)` to trigger the
/// next message to be sent to the calling process. Notice that chunked encoding can add headers
/// so that there are more headers in the stream_end message than in stream_start.
/// 
/// When streaming to a file, using the option `Stream(filename)`, the message
/// `#(http, #(RequestId, saved_to_file))` is sent.
/// 
/// Default strem option is `StreamNone`, which means buffer and send the entire response in one final message.
/// 
pub fn async_stream(config: Configuration, which: Stream) -> Configuration {
  Builder(..config, stream: which)
}

/// Send a synchronus HTTP request of unicode data.
///
pub fn dispatch(
  config: Configuration,
  request: Request(String),
) -> Result(Response(String), HttpError) {
  let request = request.map(request, bit_array.from_string)
  use resp <- result.try(dispatch_bits(config, request))

  case bit_array.to_string(resp.body) {
    Ok(body) -> Ok(response.set_body(resp, body))
    Error(_) -> Error(InvalidUtf8Response)
  }
}

/// Send a asynchronus HTTP request of unicode data.
///
pub fn async_dispatch(
  config: Configuration,
  request: Request(String),
) -> Result(Reference, HttpError) {
  let request = request.map(request, bit_array.from_string)
  use request_id <- result.try(
    async_dispatch_bits(config, request)
    // TODO Is this the right error? Should I create a unique streaming error?
    |> result.replace_error(InvalidUtf8Response),
  )
  Ok(request_id)
}

// TODO: refine error type
/// Send a HTTP asychronous request of unicode data using the default configuration.
///
/// If you wish to use some other configuration use `async_dispatch` instead.
///
pub fn async_send(req: Request(String)) -> Result(Reference, HttpError) {
  configure()
  |> async_dispatch(req)
}

// TODO: refine error type
/// Send a HTTP request of unicode data using the default configuration.
///
/// If you wish to use some other configuration use `dispatch` instead.
///
pub fn send(req: Request(String)) -> Result(Response(String), HttpError) {
  configure()
  |> dispatch(req)
}

fn prepare_headers(
  headers: List(#(String, String)),
) -> List(#(Charlist, Charlist)) {
  prepare_headers_loop(headers, [], False)
}

fn prepare_headers_loop(
  in: List(#(String, String)),
  out: List(#(Charlist, Charlist)),
  user_agent_set: Bool,
) -> List(#(Charlist, Charlist)) {
  case in {
    [] if user_agent_set -> out
    [] -> [default_user_agent(), ..out]
    [#(k, v), ..in] -> {
      let user_agent_set = user_agent_set || k == "user-agent"
      let out = [#(charlist.from_string(k), charlist.from_string(v)), ..out]
      prepare_headers_loop(in, out, user_agent_set)
    }
  }
}
