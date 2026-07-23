otel_request_line <- function(request) {
  jsonlite::toJSON(request, auto_unbox = TRUE, null = "null")
}

recorded_mcplite_spans <- function(recording) {
  spans <- unname(recording$traces)
  is_mcplite <- vapply(
    spans,
    function(span) {
      identical(
        span$instrumentation_scope$name,
        "r.package.mcplite"
      )
    },
    logical(1)
  )

  spans[is_mcplite]
}

recorded_spans_named <- function(recording, name) {
  spans <- unname(recording$traces)
  spans[vapply(
    spans,
    function(span) identical(span$name, name),
    logical(1)
  )]
}

packed_test_remote_context <- function(tracestate = NULL) {
  parent <- otel::start_span(
    "test.remote.parent",
    options = list(parent = NA),
    tracer = "mcplite.tests.context"
  )
  on.exit(otel::end_span(parent), add = TRUE)

  headers <- otel::with_active_span(
    parent,
    otel::pack_http_context()
  )

  if (!is.null(tracestate)) {
    remote_context <- otel::extract_http_context(
      c(as.list(headers), list(tracestate = tracestate))
    )
    headers <- remote_context$to_http_headers()
  }

  as.list(headers)
}

record_initialized_request <- function(
  request,
  state = new_test_state(),
  ambient_parent_name = NULL
) {
  initialized <- mcplite:::handle_input_line(
    otel_request_line(initialize_request()),
    state
  )

  otelsdk::with_otel_record(
    {
      request <- force(request)
      record_request <- function() {
        mcplite:::handle_input_line(
          otel_request_line(request),
          initialized$state
        )
      }

      if (is.null(ambient_parent_name)) {
        record_request()
      } else {
        ambient_parent <- otel::start_span(
          ambient_parent_name,
          options = list(parent = NA),
          tracer = "mcplite.tests.context"
        )
        tryCatch(
          otel::with_active_span(ambient_parent, record_request()),
          finally = otel::end_span(ambient_parent)
        )
      }
    },
    what = "traces"
  )
}

expect_single_mcplite_span <- function(
  recording,
  name = NULL,
  method = NULL,
  server_kind = FALSE,
  info = NULL
) {
  spans <- recorded_mcplite_spans(recording)
  expect_identical(length(spans), 1L, info = info)

  if (length(spans) != 1L) {
    return(NULL)
  }

  span <- spans[[1]]
  if (!is.null(name)) {
    expect_identical(span$name, name, info = info)
  }
  if (server_kind) {
    expect_identical(span$kind, "server", info = info)
  }
  if (!is.null(method)) {
    expect_identical(span$attributes[["mcp.method.name"]], method, info = info)
  }

  span
}

run_disabled_tracing_dispatch <- function(
  otel_env = NULL,
  env = parent.frame()
) {
  mode <- if (testthat::is_checking()) "installed" else "source"
  libpaths <- paste(capture.output(dput(.libPaths())), collapse = "")
  source_root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  script <- sprintf(".libPaths(%s)", libpaths)

  if (identical(mode, "source")) {
    script <- c(
      script,
      sprintf("source_root <- %s", encodeString(source_root, quote = '"')),
      "r_dir <- file.path(source_root, 'R')",
      "paths <- sort(list.files(r_dir, '[.]R$', full.names = TRUE))",
      "for (path in paths) sys.source(path, envir = globalenv())",
      "pkg <- globalenv()"
    )
  } else {
    script <- c(script, "pkg <- loadNamespace('mcplite')")
  }

  script <- c(
    script,
    "dispatch <- get('dispatch_message', pkg, inherits = FALSE)",
    "new_state <- get('new_server_state', pkg, inherits = FALSE)",
    "validate <- get('valid_request_message', pkg, inherits = FALSE)",
    "enabled <- otel::is_tracing_enabled()",
    "cat(sprintf('TRACING_ENABLED=%s\\n', enabled))",
    "stopifnot(identical(enabled, FALSE))",
    "as.character.hostile_id <- function(x, ...) {",
    "  stop('telemetry-only coercion was forced', call. = FALSE)",
    "}",
    "request <- list(",
    "  jsonrpc = '2.0',",
    "  id = structure('ping-id', class = c('hostile_id', 'character')),",
    "  method = 'ping'",
    ")",
    "valid <- validate(request)",
    "cat(sprintf('ENVELOPE_VALID=%s\\n', valid))",
    "stopifnot(isTRUE(valid))",
    "state <- new_state(list())",
    "result <- dispatch(request, state)",
    "empty <- structure(list(), names = character())",
    "expected <- list(jsonrpc = '2.0', id = request$id, result = empty)",
    "if (!identical(result$response, expected) ||",
    "    !identical(result$state, state)) {",
    "  stop('Canonical ping response or state changed.', call. = FALSE)",
    "}",
    "cat('DISPATCH_OK=TRUE\\n')"
  )

  script_path <- withr::local_tempfile(fileext = ".R", .local_envir = env)
  writeLines(script, script_path)
  child_env <- Sys.getenv()
  child_env <- child_env[!startsWith(names(child_env), "OTEL_")]
  child_env[["R_TESTS"]] <- ""
  if (!is.null(otel_env)) {
    child_env[["OTEL_ENV"]] <- otel_env
  }

  result <- processx::run(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", script_path),
    error_on_status = FALSE,
    env = child_env
  )
  result$mode <- mode
  result
}

test_that("disabled tracing does not force request telemetry metadata", {
  skip_if_not_installed("processx")

  cases <- list(production = NULL, dev = "dev")
  for (i in seq_along(cases)) {
    result <- run_disabled_tracing_dispatch(cases[[i]])
    diagnostics <- paste(
      sprintf(
        "case: %s; package mode: %s; status: %s",
        names(cases)[[i]],
        result$mode,
        result$status
      ),
      paste0("stdout:\n", result$stdout),
      paste0("stderr:\n", result$stderr),
      sep = "\n"
    )

    expect_match(result$stdout, "TRACING_ENABLED=FALSE", info = diagnostics)
    expect_match(result$stdout, "ENVELOPE_VALID=TRUE", info = diagnostics)
    expect_identical(result$status, 0L, info = diagnostics)
    if (!identical(result$status, 0L)) {
      next
    }
    expect_match(result$stdout, "DISPATCH_OK=TRUE", info = diagnostics)
  }
})

test_that("successful initialized tool calls record one MCP server span", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    tool_call_request(
      name = "hello",
      arguments = list(name = "Ada")
    )
  )

  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 3L,
      result = list(
        content = list(list(type = "text", text = "Hello, Ada!")),
        isError = FALSE
      )
    )
  )

  span <- expect_single_mcplite_span(
    recording,
    name = "tools/call hello",
    method = "tools/call",
    server_kind = TRUE
  )
  if (!is.null(span)) {
    expect_identical(span$attributes[["gen_ai.tool.name"]], "hello")
    expect_identical(
      span$attributes[["gen_ai.operation.name"]],
      "execute_tool"
    )
    expect_identical(span$attributes[["jsonrpc.request.id"]], "3")
    expect_identical(
      span$attributes[["mcp.protocol.version"]],
      "2025-11-25"
    )
    expect_identical(span$attributes[["network.transport"]], "pipe")
  }
})

test_that("contained tool errors retain MCP results and record tool errors", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    tool_call_request(name = "explode")
  )

  response <- recording$value$response
  expect_named(response, c("jsonrpc", "id", "result"))
  expect_identical(response$jsonrpc, "2.0")
  expect_identical(response$id, 3L)
  expect_named(response$result, c("content", "isError"))
  expect_true(response$result$isError)
  expect_null(response$error)
  expect_length(response$result$content, 1L)
  expect_named(response$result$content[[1]], c("type", "text"))
  expect_identical(response$result$content[[1]]$type, "text")
  expect_type(response$result$content[[1]]$text, "character")
  expect_length(response$result$content[[1]]$text, 1L)

  span <- expect_single_mcplite_span(recording)
  if (!is.null(span)) {
    expect_identical(span$status, "error")
    expect_identical(span$attributes[["error.type"]], "tool_error")
    expect_null(span$attributes[["rpc.response.status_code"]])
  }
})

test_that("unknown tools retain JSON-RPC errors and record codes", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    tool_call_request(name = "missing")
  )

  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 3L,
      error = list(
        code = -32602,
        message = "Unknown tool"
      )
    )
  )

  span <- expect_single_mcplite_span(recording)
  if (!is.null(span)) {
    expect_identical(span$status, "error")
    expect_identical(span$attributes[["error.type"]], "-32602")
    expect_identical(
      span$attributes[["rpc.response.status_code"]],
      "-32602"
    )
  }
})

test_that("remaining MCP operations require spans without behavior changes", {
  skip_if_not_installed("otelsdk")

  initialized <- mcplite:::handle_input_line(
    otel_request_line(initialize_request()),
    new_test_state()
  )
  initialized_state <- initialized$state
  client_initialized_state <- initialized_state
  client_initialized_state$client_initialized <- TRUE

  cases <- list(
    list(
      method = "initialize",
      request = initialize_request(protocol_version = "9999-01-01"),
      state = new_test_state(),
      expected_state = list(
        initialized = TRUE,
        protocol_version = "2025-11-25",
        client_initialized = FALSE
      ),
      request_id = "1",
      protocol_version = "2025-11-25",
      check_response = function(response) {
        expect_named(response, c("jsonrpc", "id", "result"))
        expect_identical(response$jsonrpc, "2.0")
        expect_identical(response$id, 1L)
        expect_named(
          response$result,
          c("protocolVersion", "capabilities", "serverInfo")
        )
        expect_identical(response$result$protocolVersion, "2025-11-25")
        expect_identical(
          response$result$capabilities,
          list(tools = list(listChanged = FALSE))
        )
        expect_identical(response$result$serverInfo$name, "mcplite")
        expect_type(response$result$serverInfo$version, "character")
      }
    ),
    list(
      method = "notifications/initialized",
      request = initialized_notification(),
      state = initialized_state,
      expected_state = client_initialized_state,
      request_id = NULL,
      protocol_version = "2025-11-25",
      check_response = function(response) {
        expect_null(response)
      }
    ),
    list(
      method = "ping",
      request = list(jsonrpc = "2.0", id = 99L, method = "ping"),
      state = new_test_state(),
      expected_state = list(
        initialized = FALSE,
        protocol_version = NULL,
        client_initialized = FALSE
      ),
      request_id = "99",
      protocol_version = NULL,
      check_response = function(response) {
        expect_identical(
          response,
          list(jsonrpc = "2.0", id = 99L, result = named_list())
        )
      }
    ),
    list(
      method = "tools/list",
      request = tools_list_request(),
      state = initialized_state,
      expected_state = initialized_state,
      request_id = "2",
      protocol_version = "2025-11-25",
      check_response = function(response) {
        expect_named(response, c("jsonrpc", "id", "result"))
        expect_identical(response$jsonrpc, "2.0")
        expect_identical(response$id, 2L)
        expect_named(response$result, "tools")
        expect_identical(
          vapply(response$result$tools, `[[`, character(1), "name"),
          c("status", "hello", "explode", "chatty")
        )
        expect_null(response$result$nextCursor)
      }
    ),
    list(
      method = "resources/list",
      request = list(
        jsonrpc = "2.0",
        id = 10L,
        method = "resources/list"
      ),
      state = initialized_state,
      expected_state = initialized_state,
      request_id = "10",
      protocol_version = "2025-11-25",
      error_code = "-32601",
      check_response = function(response) {
        expect_identical(
          response,
          list(
            jsonrpc = "2.0",
            id = 10L,
            error = list(code = -32601, message = "Method not found")
          )
        )
      }
    )
  )

  for (case in cases) {
    recording <- otelsdk::with_otel_record(
      mcplite:::handle_input_line(
        otel_request_line(case$request),
        case$state
      ),
      what = "traces"
    )
    result <- recording$value

    case$check_response(result$response)
    expect_identical(
      result$state$initialized,
      case$expected_state$initialized,
      info = case$method
    )
    expect_identical(
      result$state$protocol_version,
      case$expected_state$protocol_version,
      info = case$method
    )
    expect_identical(
      result$state$client_initialized,
      case$expected_state$client_initialized,
      info = case$method
    )

    span <- expect_single_mcplite_span(
      recording,
      name = case$method,
      method = case$method,
      server_kind = TRUE,
      info = case$method
    )
    if (!is.null(span)) {
      expect_identical(
        span$attributes[["jsonrpc.request.id"]],
        case$request_id
      )
      expect_identical(span$attributes[["network.transport"]], "pipe")
      expect_identical(
        span$attributes[["mcp.protocol.version"]],
        case$protocol_version
      )

      if (is.null(case$error_code)) {
        expect_false(identical(span$status, "error"))
        expect_null(span$attributes[["error.type"]])
        expect_null(span$attributes[["rpc.response.status_code"]])
      } else {
        expect_identical(span$status, "error")
        expect_identical(
          span$attributes[["error.type"]],
          case$error_code
        )
        expect_identical(
          span$attributes[["rpc.response.status_code"]],
          case$error_code
        )
      }
    }
  }
})

test_that("valid traceparent overrides ambient parent and hides _meta", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    {
      remote_headers <- packed_test_remote_context()
      expect_true("traceparent" %in% names(remote_headers))
      request <- tool_call_request(
        id = 41L,
        name = "hello",
        arguments = list(name = "Ada")
      )
      request$params[["_meta"]] <- remote_headers
      request
    },
    ambient_parent_name = "test.ambient.parent"
  )
  # hello(name) rejects extra arguments, so success proves that _meta remains
  # metadata instead of becoming an extra tool argument.
  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 41L,
      result = list(
        content = list(list(type = "text", text = "Hello, Ada!")),
        isError = FALSE
      )
    )
  )

  span <- expect_single_mcplite_span(recording)
  remote_parents <- recorded_spans_named(recording, "test.remote.parent")
  ambient_parents <- recorded_spans_named(recording, "test.ambient.parent")
  expect_length(remote_parents, 1L)
  expect_length(ambient_parents, 1L)

  if (
    !is.null(span) &&
      length(remote_parents) == 1L &&
      length(ambient_parents) == 1L
  ) {
    expect_identical(span$parent, remote_parents[[1]]$span_id)
    expect_identical(span$trace_id, remote_parents[[1]]$trace_id)
  }
})

test_that("valid tracestate is accepted with remote parent context", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    {
      remote_headers <- packed_test_remote_context("vendor=value")
      expect_identical(remote_headers[["tracestate"]], "vendor=value")
      request <- tool_call_request(
        id = 42L,
        name = "hello",
        arguments = list(name = "Ada")
      )
      request$params[["_meta"]] <- remote_headers
      request
    },
    ambient_parent_name = "test.ambient.parent"
  )
  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 42L,
      result = list(
        content = list(list(type = "text", text = "Hello, Ada!")),
        isError = FALSE
      )
    )
  )

  span <- expect_single_mcplite_span(recording)
  remote_parents <- recorded_spans_named(recording, "test.remote.parent")
  expect_length(remote_parents, 1L)

  if (!is.null(span) && length(remote_parents) == 1L) {
    expect_identical(span$parent, remote_parents[[1]]$span_id)
    expect_identical(span$trace_id, remote_parents[[1]]$trace_id)
  }
})

test_that("malformed remote context is ignored without protocol conditions", {
  skip_if_not_installed("otelsdk")

  cases <- list(
    list(
      name = "scalar _meta",
      meta = function() "not-a-list"
    ),
    list(
      name = "missing traceparent",
      meta = function() list(tracestate = "vendor=value")
    ),
    list(
      name = "malformed traceparent",
      meta = function() list(traceparent = "not-a-traceparent")
    ),
    list(
      name = "wrong-shaped traceparent",
      meta = function() list(traceparent = list("not-a-string"))
    ),
    list(
      name = "wrong-shaped tracestate",
      meta = function() {
        headers <- packed_test_remote_context()
        headers$tracestate <- list("vendor=value")
        headers
      }
    )
  )

  for (i in seq_along(cases)) {
    case <- cases[[i]]
    request_id <- 50L + i
    ambient_name <- paste0("test.ambient.parent.", i)
    recording <- NULL
    expect_no_condition(
      recording <- record_initialized_request(
        {
          request <- tool_call_request(
            id = request_id,
            name = "hello",
            arguments = list(name = "Ada")
          )
          request$params[["_meta"]] <- case$meta()
          request
        },
        ambient_parent_name = ambient_name
      )
    )

    expect_identical(
      recording$value$response,
      list(
        jsonrpc = "2.0",
        id = request_id,
        result = list(
          content = list(list(type = "text", text = "Hello, Ada!")),
          isError = FALSE
        )
      ),
      info = case$name
    )

    span <- expect_single_mcplite_span(recording, info = case$name)
    ambient_parents <- recorded_spans_named(recording, ambient_name)
    expect_identical(length(ambient_parents), 1L, info = case$name)

    if (!is.null(span) && length(ambient_parents) == 1L) {
      expect_identical(
        span$parent,
        ambient_parents[[1]]$span_id,
        info = case$name
      )
      expect_identical(
        span$trace_id,
        ambient_parents[[1]]$trace_id,
        info = case$name
      )
    }
  }
})

test_that("ambient parentage remains when remote context is absent", {
  skip_if_not_installed("otelsdk")

  recording <- record_initialized_request(
    tool_call_request(
      id = 60L,
      name = "hello",
      arguments = list(name = "Ada")
    ),
    ambient_parent_name = "test.ambient.parent"
  )

  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 60L,
      result = list(
        content = list(list(type = "text", text = "Hello, Ada!")),
        isError = FALSE
      )
    )
  )

  span <- expect_single_mcplite_span(recording)
  ambient_parents <- recorded_spans_named(recording, "test.ambient.parent")
  expect_length(ambient_parents, 1L)

  if (!is.null(span) && length(ambient_parents) == 1L) {
    expect_identical(span$parent, ambient_parents[[1]]$span_id)
    expect_identical(span$trace_id, ambient_parents[[1]]$trace_id)
  }
})

test_that("tool-authored spans nest under one automatic server span", {
  skip_if_not_installed("otelsdk")

  nested_tool <- mcplite::tool(
    function(value) {
      otel::start_local_active_span(
        "test.tool.child",
        tracer = "mcplite.tests.tool"
      )
      paste0("nested:", value)
    },
    name = "nested",
    description = "Start a child span and return normally.",
    arguments = list(value = mcplite::type_string("Value to return."))
  )
  recording <- record_initialized_request(
    tool_call_request(
      id = 70L,
      name = "nested",
      arguments = list(value = "child-value")
    ),
    state = mcplite:::new_server_state(list(nested_tool))
  )

  expect_identical(
    recording$value$response,
    list(
      jsonrpc = "2.0",
      id = 70L,
      result = list(
        content = list(list(type = "text", text = "nested:child-value")),
        isError = FALSE
      )
    )
  )

  operation_span <- expect_single_mcplite_span(
    recording,
    name = "tools/call nested",
    server_kind = TRUE
  )
  child_spans <- recorded_spans_named(recording, "test.tool.child")
  expect_length(child_spans, 1L)
  expect_length(unname(recording$traces), 2L)

  if (!is.null(operation_span) && length(child_spans) == 1L) {
    child_span <- child_spans[[1]]
    expect_identical(child_span$kind, "internal")
    expect_identical(child_span$parent, operation_span$span_id)
    expect_identical(child_span$trace_id, operation_span$trace_id)
  }
})

test_that("operation span attributes exclude private request and result data", {
  skip_if_not_installed("otelsdk")

  argument_sentinel <- "PRIVATE_ARGUMENT_7a420b"
  result_sentinel <- "PRIVATE_RESULT_6d40f1"
  raw_message_sentinel <- "PRIVATE_RAW_MESSAGE_f2c8d3"
  meta_sentinel <- "PRIVATE_META_954eac"
  condition_sentinel <- "PRIVATE_CONDITION_2fb941"
  traceparent_sentinel <- paste0(
    "00-11111111111111111111111111111111-",
    "2222222222222222-01"
  )
  tracestate_sentinel <- "privacyvendor=private-tracestate-35d79e"

  privacy_tool <- mcplite::tool(
    function(secret) {
      invisible(secret)
      result_sentinel
    },
    name = "privacy_success",
    description = "Return a distinctive private result.",
    arguments = list(secret = mcplite::type_string("Private value."))
  )
  error_tool <- mcplite::tool(
    function(secret) {
      invisible(secret)
      stop(condition_sentinel, call. = FALSE)
    },
    name = "privacy_error",
    description = "Throw a distinctive contained condition.",
    arguments = list(secret = mcplite::type_string("Private value."))
  )
  initialized <- mcplite:::handle_input_line(
    otel_request_line(initialize_request()),
    mcplite:::new_server_state(list(privacy_tool, error_tool))
  )

  success_request <- tool_call_request(
    id = 71L,
    name = "privacy_success",
    arguments = list(secret = argument_sentinel)
  )
  success_request$rawMessageMarker <- raw_message_sentinel
  success_request$params[["_meta"]] <- list(
    traceparent = traceparent_sentinel,
    tracestate = tracestate_sentinel,
    private = meta_sentinel
  )
  error_request <- tool_call_request(
    id = 72L,
    name = "privacy_error",
    arguments = list(secret = argument_sentinel)
  )
  error_request$rawMessageMarker <- raw_message_sentinel
  error_request$params[["_meta"]] <- success_request$params[["_meta"]]
  success_line <- otel_request_line(success_request)
  error_line <- otel_request_line(error_request)

  recording <- otelsdk::with_otel_record(
    list(
      success = mcplite:::handle_input_line(
        success_line,
        initialized$state
      ),
      error = mcplite:::handle_input_line(
        error_line,
        initialized$state
      )
    ),
    what = "traces"
  )

  expect_identical(
    recording$value$success$response,
    list(
      jsonrpc = "2.0",
      id = 71L,
      result = list(
        content = list(list(type = "text", text = result_sentinel)),
        isError = FALSE
      )
    )
  )
  expect_identical(
    recording$value$error$response,
    list(
      jsonrpc = "2.0",
      id = 72L,
      result = list(
        content = list(list(type = "text", text = condition_sentinel)),
        isError = TRUE
      )
    )
  )

  operation_spans <- recorded_mcplite_spans(recording)
  expect_length(operation_spans, 2L)

  forbidden_name_parts <- c(
    "argument",
    "result",
    "content",
    "message",
    "_meta",
    "traceparent",
    "tracestate"
  )
  private_values <- c(
    argument_sentinel,
    result_sentinel,
    raw_message_sentinel,
    meta_sentinel,
    condition_sentinel,
    traceparent_sentinel,
    tracestate_sentinel,
    success_line,
    error_line
  )

  for (span in operation_spans) {
    attribute_names <- names(span$attributes)
    scalar_attribute_values <- vapply(
      span$attributes,
      function(value) {
        if (is.atomic(value) && length(value) == 1L) {
          as.character(value)
        } else {
          NA_character_
        }
      },
      character(1)
    )
    scalar_attribute_values <- scalar_attribute_values[
      !is.na(scalar_attribute_values)
    ]

    for (name_part in forbidden_name_parts) {
      expect_false(
        any(grepl(name_part, tolower(attribute_names), fixed = TRUE)),
        info = span$name
      )
    }
    for (private_value in private_values) {
      expect_false(
        any(grepl(private_value, scalar_attribute_values, fixed = TRUE)),
        info = span$name
      )
    }
  }
})

test_that("invalid inputs do not create MCP operation spans", {
  skip_if_not_installed("otelsdk")

  cases <- list(
    list(
      name = "blank input",
      line = "",
      response = NULL
    ),
    list(
      name = "JSON parse failure",
      line = "{not-json}",
      response = list(
        jsonrpc = "2.0",
        id = NULL,
        error = list(code = -32700, message = "Parse error")
      )
    ),
    list(
      name = "missing method",
      line = otel_request_line(list(jsonrpc = "2.0", id = 73L)),
      response = list(
        jsonrpc = "2.0",
        id = 73L,
        error = list(code = -32600, message = "Invalid Request")
      )
    ),
    list(
      name = "top-level array",
      line = "[1,2]",
      response = list(
        jsonrpc = "2.0",
        id = NULL,
        error = list(code = -32600, message = "Invalid Request")
      )
    )
  )

  for (case in cases) {
    state <- new_test_state()
    recording <- otelsdk::with_otel_record(
      mcplite:::handle_input_line(case$line, state),
      what = "traces"
    )

    expect_identical(
      recording$value$response,
      case$response,
      info = case$name
    )
    expect_identical(recording$value$state, state, info = case$name)
    expect_identical(
      length(recorded_mcplite_spans(recording)),
      0L,
      info = case$name
    )
  }
})
