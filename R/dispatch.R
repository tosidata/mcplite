new_server_state <- function(tools, instructions = NULL) {
  list(
    config = list(
      registry = as_tool_registry(tools),
      instructions = instructions,
      server_info = list(
        name = "mcplite",
        version = package_version_string()
      )
    ),
    legacy = list(
      initialized = FALSE,
      protocol_version = NULL,
      client_initialized = FALSE
    )
  )
}

modern_metadata_keys <- c(
  protocol_version = "io.modelcontextprotocol/protocolVersion",
  client_capabilities = "io.modelcontextprotocol/clientCapabilities",
  client_info = "io.modelcontextprotocol/clientInfo",
  log_level = "io.modelcontextprotocol/logLevel"
)

modern_logging_levels <- c(
  "alert",
  "critical",
  "debug",
  "emergency",
  "error",
  "info",
  "notice",
  "warning"
)

message_has_id <- function(message) {
  is.list(message) && "id" %in% names(message)
}

valid_message_id <- function(id) {
  is_string_id <- is_scalar_character(id)
  is_integer_id <- is_scalar_numeric(id) &&
    is.finite(id) &&
    id == floor(id)

  is_string_id || is_integer_id
}

valid_request_message <- function(message) {
  is_named_list(message) &&
    identical(message[["jsonrpc"]], "2.0") &&
    is_scalar_character(message[["method"]]) &&
    (!message_has_id(message) || valid_message_id(message[["id"]]))
}

is_legacy_required_string <- function(x) {
  is_scalar_character(x) && nzchar(x)
}

valid_legacy_client_info <- function(client_info) {
  is_named_list(client_info) &&
    is_legacy_required_string(client_info[["name"]]) &&
    is_legacy_required_string(client_info[["version"]]) &&
    (is.null(client_info[["title"]]) ||
      is_legacy_required_string(client_info[["title"]]))
}

valid_legacy_initialize_params <- function(params) {
  is_named_list(params) &&
    is_legacy_required_string(params[["protocolVersion"]]) &&
    is_named_list(params[["capabilities"]]) &&
    valid_legacy_client_info(params[["clientInfo"]])
}

request_has_modern_intent <- function(message) {
  if (identical(message[["method"]], "server/discover")) {
    return(TRUE)
  }

  params <- message[["params"]]
  if (!is.list(params) || !("_meta" %in% names(params))) {
    return(FALSE)
  }

  meta <- params[["_meta"]]
  is.list(meta) && any(names(meta) %in% modern_metadata_keys)
}

build_request_context <- function(message, state) {
  params <- message[["params"]]
  if (!request_has_modern_intent(message)) {
    protocol_version <- state$legacy$protocol_version
    error <- NULL
    if (identical(message[["method"]], "initialize")) {
      if (!valid_legacy_initialize_params(params)) {
        protocol_version <- NULL
        error <- jsonrpc_invalid_params(
          message[["id"]],
          message = "Invalid initialize params"
        )
      } else {
        protocol_version <- negotiate_legacy_protocol_version(
          params[["protocolVersion"]]
        )
      }
    }

    return(list(
      context = list(
        era = "legacy",
        protocol_version = protocol_version,
        telemetry_protocol_version = protocol_version
      ),
      error = error
    ))
  }

  result <- list(
    context = list(
      era = "modern",
      protocol_version = NULL,
      telemetry_protocol_version = NULL
    ),
    error = jsonrpc_invalid_params(
      message[["id"]],
      message = "Invalid modern request metadata"
    )
  )

  if (
    !is_named_list(params) ||
      !("_meta" %in% names(params)) ||
      !is_named_list(params[["_meta"]])
  ) {
    return(result)
  }

  meta <- params[["_meta"]]
  version <- meta[[modern_metadata_keys[["protocol_version"]]]]
  if (!is_scalar_character(version)) {
    return(result)
  }

  # Keep the modern requested version even if metadata validation fails.
  result$context$telemetry_protocol_version <- version
  if (!(version %in% modern_supported_protocol_versions)) {
    result$error <- jsonrpc_unsupported_protocol_version(
      message[["id"]],
      version
    )
    return(result)
  }

  capabilities_key <- modern_metadata_keys[["client_capabilities"]]
  if (
    !(capabilities_key %in% names(meta)) ||
      !is_named_list(meta[[capabilities_key]])
  ) {
    return(result)
  }

  client_info_key <- modern_metadata_keys[["client_info"]]
  client_info <- meta[[client_info_key]]
  if (client_info_key %in% names(meta)) {
    valid_client_info <- is_named_list(client_info) &&
      is_scalar_character(client_info[["name"]]) &&
      is_scalar_character(client_info[["version"]])
    if (!valid_client_info) {
      return(result)
    }
  }

  log_level_key <- modern_metadata_keys[["log_level"]]
  if (log_level_key %in% names(meta)) {
    log_level <- meta[[log_level_key]]
    if (
      !is_scalar_character(log_level) ||
        !(log_level %in% modern_logging_levels)
    ) {
      return(result)
    }
  }

  result$context$protocol_version <- version
  result$error <- NULL
  result
}

valid_tools_list_params <- function(params) {
  if (is.null(params)) {
    return(TRUE)
  }

  if (!is_named_list(params)) {
    return(FALSE)
  }

  if (!all(names(params) %in% c("cursor", "_meta"))) {
    return(FALSE)
  }

  meta <- params[["_meta"]]
  valid_meta <- !("_meta" %in% names(params)) ||
    (is.list(meta) && length(meta) == 0) ||
    is_named_list(meta)

  valid_meta &&
    (!("cursor" %in% names(params)) || is.null(params[["cursor"]]))
}

#' @importFrom jsonlite parse_json
handle_input_line <- function(line, state) {
  if (length(line) == 0 || !nzchar(line)) {
    return(list(response = NULL, state = state))
  }

  message <- tryCatch(
    parse_json(line, simplifyVector = FALSE),
    error = function(cnd) {
      NULL
    }
  )

  if (is.null(message)) {
    return(list(response = jsonrpc_parse_error(), state = state))
  }

  dispatch_message(message, state)
}

dispatch_message <- function(message, state) {
  if (!valid_request_message(message)) {
    id <- NULL
    if (message_has_id(message) && valid_message_id(message[["id"]])) {
      id <- message[["id"]]
    }

    return(list(
      response = jsonrpc_invalid_request(id),
      state = state
    ))
  }

  # Activate for this dispatch frame so the complete valid operation stays
  # inside the span, including context validation and tool execution.
  span <- start_mcp_server_span(message)
  context_result <- build_request_context(message, state)
  context <- context_result$context

  if (!is.null(context_result$error)) {
    response <- if (message_has_id(message)) context_result$error
    result <- list(response = response, state = state)
  } else if (identical(context$era, "modern")) {
    result <- dispatch_modern_message(message, state, context)
  } else {
    result <- dispatch_legacy_message(message, state, context)
  }

  result$response <- decorate_modern_result(
    result$response,
    context,
    state$config$server_info
  )

  record_mcp_server_span_outcome(span, result$response, context)

  result
}

dispatch_modern_message <- function(message, state, context) {
  # Modern notifications are self-contained but remain no-response JSON-RPC
  # messages; unsupported notification methods also produce no response.
  if (!message_has_id(message)) {
    return(list(response = NULL, state = state))
  }

  method <- message[["method"]]
  id <- message[["id"]]

  if (identical(method, "server/discover")) {
    result <- compact_nulls(list(
      supportedVersions = as.list(discovery_supported_protocol_versions),
      capabilities = list(
        tools = named_list(listChanged = FALSE)
      ),
      instructions = state$config$instructions,
      ttlMs = modern_public_cache_ttl_ms,
      cacheScope = "public"
    ))

    return(list(
      response = jsonrpc_response(id, result = result),
      state = state
    ))
  }

  if (identical(method, "tools/list")) {
    return(handle_tools_list_request(message, state, context))
  }

  if (identical(method, "tools/call")) {
    return(handle_tool_call_request(message, state, context))
  }

  list(response = jsonrpc_method_not_found(id), state = state)
}

dispatch_legacy_message <- function(message, state, context) {
  method <- message[["method"]]

  if (
    identical(method, "notifications/initialized") && message_has_id(message)
  ) {
    return(list(
      response = jsonrpc_invalid_request(message[["id"]]),
      state = state
    ))
  }

  if (identical(method, "notifications/initialized")) {
    if (isTRUE(state$legacy$initialized)) {
      state$legacy$client_initialized <- TRUE
    }
    return(list(response = NULL, state = state))
  }

  # JSON-RPC notifications never receive responses, so only real requests
  # continue down the canonical initialize/dispatch path.
  if (!message_has_id(message)) {
    return(list(response = NULL, state = state))
  }

  id <- message[["id"]]

  if (identical(method, "initialize")) {
    return(handle_initialize_request(message, state, context))
  }

  if (identical(method, "ping")) {
    return(list(response = jsonrpc_response(id, named_list()), state = state))
  }

  if (!isTRUE(state$legacy$initialized)) {
    return(list(response = server_not_initialized_error(id), state = state))
  }

  if (identical(method, "tools/list")) {
    return(handle_tools_list_request(message, state, context))
  }

  if (identical(method, "tools/call")) {
    return(handle_tool_call_request(message, state, context))
  }

  list(response = jsonrpc_method_not_found(id), state = state)
}

decorate_modern_result <- function(response, context, server_info) {
  if (
    !identical(context$era, "modern") ||
      is.null(response) ||
      !is.null(response$error)
  ) {
    return(response)
  }

  result <- response$result
  result$resultType <- "complete"

  meta <- result[["_meta"]]
  if (!is_named_list(meta)) {
    meta <- named_list()
  }
  meta[["io.modelcontextprotocol/serverInfo"]] <- server_info
  result[["_meta"]] <- meta

  response$result <- result
  response
}

handle_tools_list_request <- function(message, state, context) {
  if (!valid_tools_list_params(message[["params"]])) {
    return(list(
      response = jsonrpc_invalid_params(message[["id"]]),
      state = state
    ))
  }

  result <- list(
    # The registry is one deterministic page; non-null cursors are rejected
    # instead of being silently ignored.
    tools = registry_tools_as_mcp(state$config$registry, context)
  )
  if (identical(context$era, "modern")) {
    result$ttlMs <- modern_public_cache_ttl_ms
    result$cacheScope <- "public"
  }

  list(
    response = jsonrpc_response(message[["id"]], result = result),
    state = state
  )
}

handle_initialize_request <- function(message, state, context) {
  state$legacy$initialized <- TRUE
  state$legacy$protocol_version <- context$protocol_version

  list(
    response = jsonrpc_response(
      message[["id"]],
      result = server_capabilities(
        protocol_version = context$protocol_version,
        instructions = state$config$instructions
      )
    ),
    state = state
  )
}

handle_tool_call_request <- function(message, state, context) {
  params <- message[["params"]]
  id <- message[["id"]]

  if (!is_named_list(params)) {
    return(list(response = jsonrpc_invalid_params(id), state = state))
  }

  name <- params[["name"]]
  if (!is_scalar_character(name)) {
    return(list(response = jsonrpc_invalid_params(id), state = state))
  }

  arguments_present <- "arguments" %in% names(params)
  arguments <- params[["arguments"]]
  if (arguments_present && !is_named_list(arguments)) {
    return(list(response = jsonrpc_invalid_params(id), state = state))
  }

  tool <- registry_tool(state$config$registry, name)

  if (is.null(tool)) {
    return(list(
      response = jsonrpc_invalid_params(id, message = "Unknown tool"),
      state = state
    ))
  }

  list(
    response = execute_tool_call(
      id,
      tool,
      if (arguments_present) arguments else named_list(),
      context
    ),
    state = state
  )
}
