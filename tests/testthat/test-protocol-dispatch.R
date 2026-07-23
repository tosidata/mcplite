test_that("supported protocol versions exclude unsupported batching versions", {
  expect_false("2025-03-26" %in% mcplite:::supported_protocol_versions)
  expect_identical(mcplite:::latest_protocol_version, "2025-11-25")
})

test_that("protocol negotiation falls back to the latest supported version", {
  expect_identical(
    mcplite:::negotiate_protocol_version("9999-01-01"),
    mcplite:::latest_protocol_version
  )
  expect_identical(
    mcplite:::negotiate_protocol_version("2025-03-26"),
    mcplite:::latest_protocol_version
  )
})

test_that("initialize returns truthful capabilities and protocol-aware instructions", {
  state <- new_test_state(instructions = "Use the tools when needed.")

  initialized <- mcplite:::dispatch_message(
    initialize_request(protocol_version = "2024-11-05"),
    state
  )

  expect_true(initialized$state$initialized)
  expect_named(initialized$response$result$capabilities, "tools")
  expect_null(initialized$response$result$capabilities$prompts)
  expect_null(initialized$response$result$capabilities$resources)
  expect_null(initialized$response$result$instructions)

  newer <- mcplite:::dispatch_message(
    initialize_request(protocol_version = "2025-11-25"),
    new_test_state(instructions = "Use the tools when needed.")
  )

  expect_identical(
    newer$response$result$instructions,
    "Use the tools when needed."
  )
})

test_that("non-lifecycle requests are rejected before initialize", {
  response <- mcplite:::dispatch_message(tools_list_request(), new_test_state())

  expect_identical(response$response$error$code, -32600)
  expect_match(response$response$error$message, "not initialized")
})

test_that("initialized notification before initialize leaves state unchanged", {
  result <- mcplite:::dispatch_message(
    initialized_notification(),
    new_test_state()
  )

  expect_null(result$response)
  expect_false(result$state$initialized)
  expect_false(result$state$client_initialized)
})

test_that("initialized notification with an id returns an error", {
  before_initialize <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "notifications/initialized"),
    new_test_state()
  )

  expect_identical(before_initialize$response$error$code, -32600)
  expect_identical(before_initialize$response$id, 1)
  expect_false(before_initialize$state$initialized)
  expect_false(before_initialize$state$client_initialized)

  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  after_initialize <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 2, method = "notifications/initialized"),
    state
  )

  expect_identical(after_initialize$response$error$code, -32600)
  expect_identical(after_initialize$response$id, 2)
  expect_true(after_initialize$state$initialized)
  expect_false(after_initialize$state$client_initialized)
})

test_that("valid initialized notifications remain no-response notifications", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  result <- mcplite:::dispatch_message(
    initialized_notification(),
    state
  )

  expect_null(result$response)
  expect_true(result$state$initialized)
  expect_true(result$state$client_initialized)
})

test_that("ping succeeds before initialize", {
  response <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 99, method = "ping"),
    new_test_state()
  )

  expect_identical(response$response$result, named_list())
})

test_that("unknown methods return JSON-RPC method not found errors", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  response <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 10, method = "resources/list"),
    state
  )

  expect_identical(response$response$error$code, -32601)
})

test_that("malformed JSON-RPC envelopes are rejected", {
  missing_jsonrpc <- mcplite:::dispatch_message(
    list(
      id = 1,
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_identical(missing_jsonrpc$response$error$code, -32600)
  expect_false(missing_jsonrpc$state$initialized)

  invalid_jsonrpc <- mcplite:::dispatch_message(
    list(
      jsonrpc = "1.0",
      id = 1,
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_identical(invalid_jsonrpc$response$error$code, -32600)
  expect_false(invalid_jsonrpc$state$initialized)

  batch_like <- mcplite:::dispatch_message(
    list(initialize_request()),
    new_test_state()
  )
  expect_identical(batch_like$response$error$code, -32600)
})

test_that("invalid JSON-RPC ids are rejected at the request boundary", {
  invalid_ids <- list(
    NULL,
    TRUE,
    1.5,
    Inf,
    NA_real_,
    c(1, 2),
    list("bad"),
    named_list(bad = "shape")
  )

  for (bad_id in invalid_ids) {
    response <- mcplite:::dispatch_message(
      list(
        jsonrpc = "2.0",
        id = bad_id,
        method = "initialize",
        params = list(protocolVersion = "2025-11-25")
      ),
      new_test_state()
    )

    expect_identical(response$response$error$code, -32600)
    expect_false(response$state$initialized)
    expect_null(response$response$id)
  }
})

test_that("string and integer JSON-RPC ids remain valid", {
  string_id <- mcplite:::dispatch_message(
    initialize_request(id = "request-1"),
    new_test_state()
  )
  expect_true(string_id$state$initialized)
  expect_identical(string_id$response$id, "request-1")

  integer_id <- mcplite:::dispatch_message(
    initialize_request(id = 1L),
    new_test_state()
  )
  expect_true(integer_id$state$initialized)
  expect_identical(integer_id$response$id, 1L)
})

test_that("notifications stay distinct from explicit null request ids", {
  initialize_notification <- mcplite:::dispatch_message(
    list(
      jsonrpc = "2.0",
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_null(initialize_notification$response)
  expect_false(initialize_notification$state$initialized)

  initialize_request_with_null_id <- mcplite:::dispatch_message(
    initialize_request(id = NULL),
    new_test_state()
  )
  expect_identical(initialize_request_with_null_id$response$error$code, -32600)
  expect_false(initialize_request_with_null_id$state$initialized)
  expect_null(initialize_request_with_null_id$response$id)
})

test_that("malformed initialize requests use the invalid params path", {
  invalid_params <- list(
    named_list(),
    list(protocolVersion = 1),
    list(
      protocolVersion = "2025-11-25",
      clientInfo = list(name = "mcplite-tests", version = "0.0.0")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = list(),
      clientInfo = list(name = "mcplite-tests", version = "0.0.0")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = named_list(),
      clientInfo = list(name = "mcplite-tests")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = named_list(),
      clientInfo = list(name = 1, version = "0.0.0")
    )
  )

  for (params in invalid_params) {
    state <- new_test_state()
    response <- mcplite:::dispatch_message(
      list(
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
        params = params
      ),
      state
    )

    expect_identical(response$response$error$code, -32602)
    expect_false(response$state$initialized)
    expect_null(response$state$protocol_version)
    expect_false(response$state$client_initialized)
  }
})

test_that("malformed JSON returns a parse error", {
  response <- mcplite:::handle_input_line("{not-json}", new_test_state())

  expect_identical(response$response$error$code, -32700)
})
