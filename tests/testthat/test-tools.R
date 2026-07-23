test_that("tools/list returns MCP tool definitions, including no-argument tools", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  response <- mcplite:::dispatch_message(tools_list_request(), state)
  tools <- response$response$result$tools

  expect_length(tools, 4)
  expect_identical(tools[[1]]$name, "status")
  expect_identical(tools[[1]]$inputSchema$properties, named_list())
  expect_identical(tools[[2]]$inputSchema$properties$name$type, "string")
  expect_null(response$response$result$nextCursor)
})

test_that("tool names use the accepted MCP name pattern", {
  expect_no_error(
    mcplite::tool(
      function() {
        "ok"
      },
      name = "abc.DEF_123-valid",
      description = "Valid tool name."
    )
  )

  invalid_names <- c("", "has space", "has,comma", "has/slash", "ümlaut")
  for (name in invalid_names) {
    expect_error(
      mcplite::tool(
        function() {
          "bad"
        },
        name = name,
        description = "Invalid tool name."
      ),
      "name"
    )
  }

  expect_error(
    mcplite::tool(
      function() {
        "bad"
      },
      name = paste(rep("a", 129), collapse = ""),
      description = "Invalid tool name."
    ),
    "name"
  )
})

test_that("local type helpers produce MCP input schemas", {
  schema_tool <- mcplite::tool(
    function(flag, count = 0L, choice, items, payload, raw) {
      list(
        flag = flag,
        count = count,
        choice = choice,
        items = items,
        payload = payload,
        raw = raw
      )
    },
    name = "schema_tool",
    description = "Exercise supported local schemas.",
    arguments = list(
      flag = mcplite::type_boolean("A flag."),
      count = mcplite::type_integer("Optional count.", required = FALSE),
      choice = mcplite::type_enum(c("a", "b"), description = "Choice."),
      items = mcplite::type_array(mcplite::type_number("Item.")),
      payload = mcplite::type_object(
        .description = "Payload.",
        label = mcplite::type_string("Label."),
        score = mcplite::type_number("Optional score.", required = FALSE)
      ),
      raw = mcplite::type_from_schema(list(
        type = "string",
        description = "Raw."
      )),
      ignored = mcplite::type_ignore()
    )
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(schema_tool)
  )$state

  response <- mcplite:::dispatch_message(tools_list_request(), state)
  schema <- response$response$result$tools[[1]]$inputSchema

  expect_identical(schema$type, "object")
  expect_false("ignored" %in% names(schema$properties))
  expect_identical(schema$properties$flag$type, "boolean")
  expect_identical(schema$properties$count$type, "integer")
  expect_identical(schema$properties$choice$type, "string")
  expect_identical(schema$properties$choice$enum, list("a", "b"))
  expect_identical(schema$properties$items$items$type, "number")
  expect_identical(schema$properties$payload$type, "object")
  expect_identical(schema$properties$payload$properties$label$type, "string")
  expect_identical(schema$properties$raw$type, "string")
  expect_identical(
    schema$required,
    list("flag", "choice", "items", "payload", "raw")
  )
})

test_that("tools/call executes tools and returns MCP content", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "hello", arguments = list(name = "Ada")),
    state
  )

  expect_false(response$response$result$isError)
  expect_identical(
    response$response$result$content[[1]]$text,
    "Hello, Ada!"
  )
})

test_that("tool execution failures are returned as MCP tool-call errors", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "explode"),
    state
  )

  expect_true(response$response$result$isError)
  expect_null(response$response$error)
  expect_identical(response$response$result$content[[1]]$text, "boom")
})

test_that("thrown JSON tool errors preserve clean MCP tool-call text", {
  json_text <- jsonlite::toJSON(
    list(error = list(code = "bad")),
    auto_unbox = TRUE
  )
  json_error_tool <- mcplite::tool(
    function() {
      stop(json_text, call. = FALSE)
    },
    name = "json_error",
    description = "Throw JSON text as a tool error."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(json_error_tool)
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "json_error"),
    state
  )
  text <- response$response$result$content[[1]]$text

  expect_null(response$response$error)
  expect_true(response$response$result$isError)
  expect_identical(text, as.character(json_text))
  expect_identical(
    jsonlite::parse_json(text, simplifyVector = FALSE),
    list(error = list(code = "bad"))
  )
})

test_that("tool result conversion failures are MCP tool-call errors", {
  unserializable_tool <- mcplite::tool(
    function() {
      new.env(parent = emptyenv())
    },
    name = "unserializable",
    description = "Return a value jsonlite cannot serialize."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(unserializable_tool)
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "unserializable"),
    state
  )

  expect_true(response$response$result$isError)
  expect_null(response$response$error)
  expect_match(
    response$response$result$content[[1]]$text,
    "Failed to convert tool result"
  )
})

test_that("tool call arguments preserve nested JSON arrays and objects", {
  nested_tool <- mcplite::tool(
    function(payload) {
      jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
    },
    name = "echo_nested",
    description = "Echo a nested payload.",
    arguments = list(
      payload = mcplite::type_array(
        mcplite::type_object(
          .description = "Payload item.",
          kind = mcplite::type_string("Kind label."),
          values = mcplite::type_array(mcplite::type_integer("Value item."))
        )
      )
    )
  )
  payload <- list(
    list(kind = "alpha", values = list(1L, 2L)),
    list(kind = "beta", values = list(3L, 4L))
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(list(nested_tool))
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(
      name = "echo_nested",
      arguments = list(payload = payload)
    ),
    state
  )
  echoed <- jsonlite::parse_json(
    response$response$result$content[[1]]$text,
    simplifyVector = FALSE
  )

  expect_false(response$response$result$isError)
  expect_identical(echoed, payload)
})

test_that("optional ellmer tools can be listed and called", {
  skip_if_not_installed("ellmer")

  ellmer_tool <- ellmer::tool(
    function(name) {
      sprintf("Hello from ellmer, %s!", name)
    },
    name = "ellmer_hello",
    description = "Say hello with an ellmer tool.",
    arguments = list(
      name = ellmer::type_string("Name to greet.")
    )
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(ellmer_tool)
  )$state

  list_response <- mcplite:::dispatch_message(tools_list_request(), state)
  call_response <- mcplite:::dispatch_message(
    tool_call_request(name = "ellmer_hello", arguments = list(name = "Ada")),
    state
  )

  expect_identical(
    list_response$response$result$tools[[1]]$inputSchema$properties$name$type,
    "string"
  )
  expect_false(call_response$response$result$isError)
  expect_identical(
    call_response$response$result$content[[1]]$text,
    "Hello from ellmer, Ada!"
  )
})

test_that("ellmer ContentToolResult success payloads preserve JSON text", {
  skip_if_not_installed("ellmer")

  json_text <- jsonlite::toJSON(list(ok = TRUE), auto_unbox = TRUE)
  ellmer_tool <- ellmer::tool(
    function() {
      ellmer::ContentToolResult(value = json_text)
    },
    name = "ellmer_json_success",
    description = "Return an ellmer JSON text result."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(ellmer_tool)
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "ellmer_json_success"),
    state
  )
  text <- response$response$result$content[[1]]$text

  expect_null(response$response$error)
  expect_false(response$response$result$isError)
  expect_identical(text, as.character(json_text))
  expect_identical(
    jsonlite::parse_json(text, simplifyVector = FALSE),
    list(ok = TRUE)
  )
})

test_that("ellmer ContentToolResult errors are MCP tool-call errors", {
  skip_if_not_installed("ellmer")

  error_text <- jsonlite::toJSON(list(error = "bad"), auto_unbox = TRUE)
  ellmer_tool <- ellmer::tool(
    function() {
      ellmer::ContentToolResult(error = error_text)
    },
    name = "ellmer_json_error",
    description = "Return an ellmer JSON text error."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(ellmer_tool)
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "ellmer_json_error"),
    state
  )
  text <- response$response$result$content[[1]]$text

  expect_null(response$response$error)
  expect_true(response$response$result$isError)
  expect_identical(text, as.character(error_text))
  expect_identical(
    jsonlite::parse_json(text, simplifyVector = FALSE),
    list(error = "bad")
  )
})

test_that("ellmer ContentToolResult condition errors use condition messages", {
  skip_if_not_installed("ellmer")

  ellmer_tool <- ellmer::tool(
    function() {
      ellmer::ContentToolResult(error = simpleError("condition boom"))
    },
    name = "ellmer_condition_error",
    description = "Return an ellmer condition error."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(ellmer_tool)
  )$state

  response <- mcplite:::dispatch_message(
    tool_call_request(name = "ellmer_condition_error"),
    state
  )

  expect_null(response$response$error)
  expect_true(response$response$result$isError)
  expect_identical(
    response$response$result$content[[1]]$text,
    "condition boom"
  )
})

test_that("tools/list validates supported params", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  with_meta <- mcplite:::dispatch_message(
    tools_list_request(params = list(`_meta` = list(traceId = "abc"))),
    state
  )
  expect_length(with_meta$response$result$tools, 4)

  invalid_requests <- list(
    list(jsonrpc = "2.0", id = 10, method = "tools/list", params = TRUE),
    list(
      jsonrpc = "2.0",
      id = 11,
      method = "tools/list",
      params = list("cursor")
    ),
    list(
      jsonrpc = "2.0",
      id = 12,
      method = "tools/list",
      params = list(cursor = 1)
    ),
    list(
      jsonrpc = "2.0",
      id = 13,
      method = "tools/list",
      params = list(page = 1)
    ),
    tools_list_request(id = 14, params = named_list(cursor = "ignored-cursor"))
  )

  for (request in invalid_requests) {
    response <- mcplite:::dispatch_message(request, state)
    expect_identical(response$response$error$code, -32602)
  }
})

test_that("unknown tool names and malformed params return JSON-RPC errors", {
  state <- mcplite:::dispatch_message(
    initialize_request(),
    new_test_state()
  )$state

  unknown_tool <- mcplite:::dispatch_message(
    tool_call_request(name = "missing"),
    state
  )
  expect_identical(unknown_tool$response$error$code, -32602)

  malformed <- mcplite:::dispatch_message(
    list(
      jsonrpc = "2.0",
      id = 11,
      method = "tools/call",
      params = list(name = "hello", arguments = list("Ada"))
    ),
    state
  )
  expect_identical(malformed$response$error$code, -32602)
})
