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

test_that("every retained legacy version lists and calls shared tools", {
  for (protocol_version in mcplite:::legacy_supported_protocol_versions) {
    initialized <- mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = protocol_version),
      new_test_state()
    )
    listed <- mcplite:::dispatch_message(
      tools_list_request(),
      initialized$state
    )
    called <- mcplite:::dispatch_message(
      tool_call_request(name = "hello", arguments = list(name = "Ada")),
      listed$state
    )

    expect_identical(
      length(listed$response$result$tools),
      4L,
      info = protocol_version
    )
    expect_identical(
      listed$response$result$tools[[2]]$inputSchema$properties$name$type,
      "string",
      info = protocol_version
    )
    expect_null(listed$response$result$resultType, info = protocol_version)
    expect_null(listed$response$result$ttlMs, info = protocol_version)
    expect_null(listed$response$result$cacheScope, info = protocol_version)
    expect_identical(
      called$response$result$content[[1]]$text,
      "Hello, Ada!",
      info = protocol_version
    )
    expect_null(called$response$result$resultType, info = protocol_version)
    expect_null(called$response$result$ttlMs, info = protocol_version)
    expect_null(called$response$result$cacheScope, info = protocol_version)
  }
})

test_that("modern tools are stateless before and after legacy traffic", {
  fresh <- new_test_state()
  initialized <- mcplite:::dispatch_message(
    legacy_initialize_request(protocol_version = "2024-11-05"),
    new_test_state()
  )
  legacy_call <- mcplite:::dispatch_message(
    tool_call_request(name = "hello", arguments = list(name = "Legacy")),
    initialized$state
  )
  states <- list(fresh = fresh, post_legacy = legacy_call$state)

  for (state_name in names(states)) {
    state <- states[[state_name]]
    listed <- mcplite:::dispatch_message(modern_tools_list_request(), state)
    called <- mcplite:::dispatch_message(
      modern_tool_call_request(
        name = "hello",
        arguments = list(name = "Modern")
      ),
      listed$state
    )

    expect_identical(listed$state, state, info = state_name)
    expect_identical(
      length(listed$response$result$tools),
      4L,
      info = state_name
    )
    expect_identical(listed$response$result$resultType, "complete")
    expect_identical(listed$response$result$cacheScope, "public")
    expect_identical(listed$response$result$ttlMs, 300000L)
    expect_identical(called$state, state, info = state_name)
    expect_identical(
      called$response$result$content[[1]]$text,
      "Hello, Modern!",
      info = state_name
    )
    expect_identical(called$response$result$resultType, "complete")
    expect_null(called$response$result$cacheScope)
    expect_null(called$response$result$ttlMs)
  }
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

test_that("complete input schemas normalize once and preserve 2020-12 keywords", {
  complete_schema <- list(
    `$schema` = "https://json-schema.org/draft/2020-12/schema",
    type = "object",
    `$defs` = list(
      Label = list(type = "string", minLength = 1L)
    ),
    properties = list(
      label = list(`$ref` = "#/$defs/Label"),
      mode = list(enum = list("brief", "full"))
    ),
    required = list("label"),
    allOf = list(list(not = list(required = list("forbidden")))),
    `if` = list(properties = list(mode = list(const = "full"))),
    then = list(required = list("mode")),
    `else` = list(properties = list(mode = list(default = "brief")))
  )
  schema_tool <- mcplite::tool(
    function(label, mode = "brief") list(label = label, mode = mode),
    name = "complete_schema",
    description = "Use a complete input schema.",
    arguments = mcplite::type_from_schema(complete_schema)
  )
  canonical <- attr(schema_tool, "mcplite_tool")

  expect_named(
    canonical,
    c("name", "description", "input_schema", "annotations", "output_schema")
  )
  expect_identical(canonical$input_schema, complete_schema)
  expect_null(canonical$arguments)

  legacy_states <- lapply(
    mcplite:::legacy_supported_protocol_versions,
    function(protocol_version) {
      mcplite:::dispatch_message(
        legacy_initialize_request(protocol_version = protocol_version),
        mcplite:::new_server_state(schema_tool)
      )$state
    }
  )
  listed <- lapply(
    legacy_states,
    function(state) {
      mcplite:::dispatch_message(tools_list_request(), state)$response
    }
  )
  listed$modern <- mcplite:::dispatch_message(
    modern_tools_list_request(),
    mcplite:::new_server_state(schema_tool)
  )$response

  for (response in listed) {
    expect_identical(response$result$tools[[1]]$inputSchema, complete_schema)
  }
})

test_that("legacy listings project only direct boolean property schemas", {
  modern_schema <- jsonlite::parse_json(
    paste0(
      '{"type":"object","properties":{"allow":true,"deny":false,',
      '"kept":{"type":"object","properties":{"nested":false}}},',
      '"required":["allow"],"additionalProperties":false,"$defs":{"Any":true}}'
    ),
    simplifyVector = FALSE
  )
  legacy_schema <- jsonlite::parse_json(
    paste0(
      '{"type":"object","properties":{"allow":{},"deny":{"not":{}},',
      '"kept":{"type":"object","properties":{"nested":false}}},',
      '"required":["allow"],"additionalProperties":false,"$defs":{"Any":true}}'
    ),
    simplifyVector = FALSE
  )
  schema_tool <- mcplite::tool(
    function(...) "ok",
    name = "boolean_schema",
    description = "Project direct boolean property schemas.",
    arguments = mcplite::type_from_schema(modern_schema),
    output_schema = mcplite::type_from_schema(modern_schema)
  )
  canonical <- attr(schema_tool, "mcplite_tool")
  modern <- mcplite:::dispatch_message(
    modern_tools_list_request(),
    mcplite:::new_server_state(schema_tool)
  )
  modern_wire <- jsonlite::parse_json(
    mcplite:::to_json(modern$response),
    simplifyVector = FALSE
  )

  expect_null(modern_wire$error)
  expect_identical(modern_wire$result$tools[[1]]$inputSchema, modern_schema)
  expect_identical(modern_wire$result$tools[[1]]$outputSchema, modern_schema)

  for (protocol_version in c("2024-11-05", "2025-06-18", "2025-11-25")) {
    initialized <- mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = protocol_version),
      modern$state
    )
    listed <- mcplite:::dispatch_message(
      tools_list_request(),
      initialized$state
    )
    legacy_wire <- jsonlite::parse_json(
      mcplite:::to_json(listed$response),
      simplifyVector = FALSE
    )
    definition <- legacy_wire$result$tools[[1]]

    expect_null(legacy_wire$error, info = protocol_version)
    expect_identical(
      definition$inputSchema,
      legacy_schema,
      info = protocol_version
    )
    if (identical(protocol_version, "2024-11-05")) {
      expect_false(
        "outputSchema" %in% names(definition),
        info = protocol_version
      )
    } else {
      expect_identical(
        definition$outputSchema,
        legacy_schema,
        info = protocol_version
      )
    }
    expect_identical(
      attr(schema_tool, "mcplite_tool"),
      canonical,
      info = protocol_version
    )
    expect_identical(
      attr(listed$state$config$registry$tools$boolean_schema, "mcplite_tool"),
      canonical,
      info = protocol_version
    )

    subsequent_modern <- mcplite:::dispatch_message(
      modern_tools_list_request(),
      listed$state
    )
    subsequent_wire <- jsonlite::parse_json(
      mcplite:::to_json(subsequent_modern$response),
      simplifyVector = FALSE
    )
    expect_null(subsequent_wire$error, info = protocol_version)
    expect_identical(
      subsequent_wire$result$tools,
      modern_wire$result$tools,
      info = protocol_version
    )
  }
})

test_that("complete input schemas require a direct object root", {
  invalid_schemas <- list(
    reference_only = list(
      `$ref` = "#/$defs/Input",
      `$defs` = list(
        Input = list(type = "object")
      )
    ),
    composition_only = list(allOf = list(list(type = "object"))),
    array = list(type = "array", items = list(type = "string")),
    missing_type = list(properties = named_list()),
    type_prefixed = list(
      typeExtension = "object",
      properties = named_list()
    )
  )

  for (case_name in names(invalid_schemas)) {
    expect_error(
      mcplite::tool(
        function() "bad",
        name = paste0("bad_", case_name),
        description = "Reject an incomplete input root.",
        arguments = mcplite::type_from_schema(invalid_schemas[[case_name]])
      ),
      "direct.*object|type.*object",
      info = case_name
    )
  }
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
    tools_list_request(id = 15, params = list(cursorExtra = NULL)),
    tools_list_request(id = 16, params = list(`_metaExtra` = named_list())),
    modern_request(
      "tools/list",
      id = 17,
      params = list(cursorExtra = NULL)
    ),
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

test_that("tools/call uses exact name and optional arguments wire keys", {
  calls <- 0L
  side_effect_tool <- mcplite::tool(
    function(value = "default") {
      calls <<- calls + 1L
      value
    },
    name = "side_effect",
    description = "Record exact tool invocation inputs.",
    arguments = list(value = mcplite::type_string(required = FALSE))
  )
  state <- mcplite:::new_server_state(side_effect_tool)

  missing_name <- modern_tool_call_request(name = "side_effect")
  missing_name$params[["nameExtension"]] <- missing_name$params[["name"]]
  missing_name$params[["name"]] <- NULL
  missing <- mcplite:::dispatch_message(missing_name, state)

  expect_identical(missing$response$error$code, -32602)
  expect_identical(calls, 0L)
  expect_identical(missing$state, state)

  null_arguments <- modern_tool_call_request(name = "side_effect")
  null_arguments$params["arguments"] <- list(NULL)
  explicit_null <- mcplite:::dispatch_message(null_arguments, state)

  expect_identical(explicit_null$response$error$code, -32602)
  expect_identical(calls, 0L)
  expect_identical(explicit_null$state, state)

  arguments_prefix <- modern_tool_call_request(name = "side_effect")
  arguments_prefix$params[["argumentsExtension"]] <- list(value = "prefix")
  defaulted <- mcplite:::dispatch_message(arguments_prefix, state)

  expect_null(defaulted$response$error)
  expect_false(defaulted$response$result$isError)
  expect_identical(defaulted$response$result$content[[1]]$text, "default")
  expect_identical(calls, 1L)
  expect_identical(defaulted$state, state)

  exact_arguments <- mcplite:::dispatch_message(
    modern_tool_call_request(
      name = "side_effect",
      arguments = list(value = "exact")
    ),
    state
  )

  expect_null(exact_arguments$response$error)
  expect_false(exact_arguments$response$result$isError)
  expect_identical(
    exact_arguments$response$result$content[[1]]$text,
    "exact"
  )
  expect_identical(calls, 2L)
  expect_identical(exact_arguments$state, state)
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
