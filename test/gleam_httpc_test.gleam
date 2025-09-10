import gleam/erlang/atom
import gleam/http.{Get, Head, Options}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/io
import gleam/string
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn request_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("test-api.service.hmrc.gov.uk")
    |> request.set_path("/hello/world")
    |> request.prepend_header("accept", "application/vnd.hmrc.1.0+json")

  let assert Ok(resp) = httpc.send(req)
  assert 200 == resp.status
  assert response.get_header(resp, "content-type") == Ok("application/json")
  assert resp.body == "{\"message\":\"Hello World\"}"
}

pub fn get_request_discards_body_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("test-api.service.hmrc.gov.uk")
    |> request.set_path("/hello/world")
    |> request.set_body("This gets dropped")
    |> request.prepend_header("accept", "application/vnd.hmrc.1.0+json")

  let assert Ok(resp) = httpc.send(req)
  assert 200 == resp.status
  assert Ok("application/json") == response.get_header(resp, "content-type")
  assert "{\"message\":\"Hello World\"}" == resp.body
}

pub fn head_request_discards_body_test() {
  let req =
    request.new()
    |> request.set_method(Head)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/get")
    |> request.set_body("This gets dropped")

  let assert Ok(resp) = httpc.send(req)
  assert 200 == resp.status
  assert Ok("application/json; charset=utf-8")
    == response.get_header(resp, "content-type")
  assert "" == resp.body
}

pub fn options_request_discards_body_test() {
  let req =
    request.new()
    |> request.set_method(Options)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/get")
    |> request.set_body("This gets dropped")

  let assert Ok(resp) = httpc.send(req)
  assert 200 == resp.status
  assert Ok("text/html; charset=utf-8")
    == response.get_header(resp, "content-type")
  assert "GET,HEAD,PUT,POST,DELETE,PATCH" == resp.body
}

pub fn invalid_tls_test() {
  let assert Ok(req) = request.to("https://expired.badssl.com")

  // This will fail because of invalid TLS
  let assert Error(httpc.FailedToConnect(
    ip4: httpc.TlsAlert("certificate_expired", _),
    ip6: _,
  )) = httpc.send(req)

  // This will fail because of invalid TLS
  let assert Error(httpc.FailedToConnect(
    ip4: httpc.TlsAlert("certificate_expired", _),
    ip6: _,
  )) =
    httpc.configure()
    |> httpc.verify_tls(True)
    |> httpc.dispatch(req)

  let assert Ok(response) =
    httpc.configure()
    |> httpc.verify_tls(False)
    |> httpc.dispatch(req)
  assert 200 == response.status
}

pub fn ipv6_test() {
  // This URL is ipv6 only
  let assert Ok(req) = request.to("https://ipv6.google.com")
  let assert Ok(resp) = httpc.send(req)
  assert 200 == resp.status
}

pub fn follow_redirects_option_test() {
  // This redirects to https://
  let assert Ok(req) = request.to("http://packages.gleam.run")

  // disabled by default
  let assert Ok(resp) = httpc.send(req)
  assert 308 == resp.status

  let assert Ok(resp) =
    httpc.configure()
    |> httpc.follow_redirects(False)
    |> httpc.dispatch(req)
  assert 308 == resp.status

  let assert Ok(resp) =
    httpc.configure()
    |> httpc.follow_redirects(True)
    |> httpc.dispatch(req)
  assert 200 == resp.status
}

pub fn default_user_agent_test() {
  let assert Ok(req) = request.to("https://echo.free.beeceptor.com")
  let assert Ok(resp) = httpc.send(req)
  assert string.contains(resp.body, "\"User-Agent\": \"gleam_httpc/")
}

pub fn custom_user_agent_test() {
  let assert Ok(req) = request.to("https://echo.free.beeceptor.com")
  let assert Ok(resp) =
    httpc.send(request.set_header(req, "user-agent", "gleam-test"))
  assert string.contains(resp.body, "\"User-Agent\": \"gleam-test")
}

pub fn timeout_success_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("httpbin.org")
    |> request.set_path("/delay/1")

  let assert Ok(resp) =
    httpc.configure()
    |> httpc.timeout(5000)
    |> httpc.dispatch(req)

  assert 200 == resp.status
}

pub fn timeout_error_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("httpbin.org")
    |> request.set_path("/delay/1")

  assert httpc.configure()
    |> httpc.timeout(200)
    |> httpc.dispatch(req)
    == Error(httpc.ResponseTimeout)
}

pub fn async_stream_self_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/stream/1")

  let config =
    httpc.configure()
    |> httpc.async_stream(httpc.StreamSelf)

  let assert Ok(request_id) = httpc.async_dispatch(config, req)

  let assert Ok(response) = httpc.async_receive(request_id, 10_000)

  // stream_start
  // #(stream_start, headers) 
  let #(stream_start, _headers) = response
  assert atom.to_string(stream_start) == "stream_start"

  // stream - 1 chunk
  // #(stream, chunk) 
  let assert Ok(response) = httpc.async_receive(request_id, 10_000)
  let #(stream, _chunk) = response
  assert atom.to_string(stream) == "stream"

  // stream_end
  // #(stream, end_info) 
  let assert Ok(response) = httpc.async_receive(request_id, 10_000)
  let #(stream_end, _end_info) = response
  assert atom.to_string(stream_end) == "stream_end"
}

pub fn async_stream_self_once_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/stream/1")

  let config =
    httpc.configure()
    |> httpc.async_stream(httpc.StreamSelfOnce)

  let assert Ok(request_id) = httpc.async_dispatch(config, req)

  // stream_start
  // #(stream_start, headers, pid) 
  let assert Ok(response) = httpc.async_receive(request_id, 10_000)
  let #(stream_start, headers_pid) = response
  assert atom.to_string(stream_start) == "stream_start"
  let #(_headers, pid) = httpc.dynamic_to_headers_pid(headers_pid)

  // stream - 1 chunks
  // #(stream_start, chunk) 
  let assert Ok(_) = httpc.async_stream_next(pid)
  let assert Ok(response) = httpc.async_receive(request_id, 10_000)
  let #(stream, _chunk) = response
  assert atom.to_string(stream) == "stream"

  // stream_end
  // #(stream_start, end_info) 
  let assert Ok(_) = httpc.async_stream_next(pid)
  let assert Ok(response) = httpc.async_receive(request_id, 10_000)
  let #(stream_end, _end_info) = response
  assert atom.to_string(stream_end) == "stream_end"
}

pub fn async_stream_file_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/stream/5")

  let config =
    httpc.configure()
    |> httpc.async_stream(httpc.StreamFile("/tmp/http_stream_test.json"))

  let assert Ok(request_id) = httpc.async_dispatch(config, req)

  let assert Ok(response) = httpc.async_receive(request_id, 1000)
  let #(saved_to_file, _) = response
  assert atom.to_string(saved_to_file) == "saved_to_file"
}

pub fn async_stream_none_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/stream/5")

  let config =
    httpc.configure()
    |> httpc.async_stream(httpc.StreamNone)

  let assert Ok(request_id) = httpc.async_dispatch(config, req)

  let assert Ok(response) = httpc.async_receive(request_id, 1000)
  let #(stream_none, _rest) = response
  assert atom.to_string(stream_none) == "stream_none"
}
