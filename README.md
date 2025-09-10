# httpc

Bindings to Erlang's built in HTTP client, `httpc`.

[![Package Version](https://img.shields.io/hexpm/v/gleam_httpc)](https://hex.pm/packages/gleam_httpc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleam_httpc/)

```sh
gleam add gleam_httpc@5
```

```gleam
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/result

pub fn send_request() {
  // Prepare a HTTP request record
  let assert Ok(base_req) =
    request.to("https://test-api.service.hmrc.gov.uk/hello/world")

  let req =
    request.prepend_header(base_req, "accept", "application/vnd.hmrc.1.0+json")

  // Send the HTTP request to the server
  use resp <- result.try(httpc.send(req))

  // We get a response record back
  assert resp.status == 200

  let content_type = response.get_header(resp, "content-type")
  assert content_type == Ok("application/json")

  assert resp.body == "{\"message\":\"Hello World\"}"

  Ok(resp)
}
```

## Http streaming requests

`httpc` supports `stream:{self, once}` mode, which is a **pull-based** approach for
accepting streamed responses. In this mode, after receiving the handler_pid, from the
`StreamStart` message, the caller must explicitly request the next stream message
using `receive_next_stream_message/1`.

```gleam
import gleam/http.{Get}
import gleam/http/request
import gleam/httpc
import gleam/process

/// Receive a streamed response from Postman Echo. The number of
/// stream chunks we receive is 1, as we specfied in the endpoint
///
pub fn stream_self_once() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("postman-echo.com")
    |> request.set_path("/stream/1")

  // Send the streaming request to the server
  let assert Ok(request_id) = httpc.send_stream_request(req)
  
  // Configure the selector
  let selector = process.new_selector() |> httpc.select_stream_messages(httpc.raw_stream_mapper())

  let assert Ok(httpc.StreamStart(_request_id_, _headers, pid)) =
    process.selector_receive(selector, 1000)

  let _nil = httpc.receive_next_stream_message(pid)
  let assert Ok(httpc.StreamChunk(_request_id_, _binary_part)) =
    process.selector_receive(selector, 1000)

  let _nil = httpc.receive_next_stream_message(pid)
  let assert Ok(httpc.StreamEnd(_request_id_, _headers)) =
    process.selector_receive(selector, 1000)
}
}
```

## Use with Erlang/OTP versions older than 26.0

Older versions of HTTPC do not verify TLS connections by default, so with them
your connection may not be secure when using this library. Consider upgrading to
a newer version of Erlang/OTP, or using a different HTTP client such as
[hackney](https://github.com/gleam-lang/hackney).
