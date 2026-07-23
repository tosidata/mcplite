new_server_state <- function(tools, instructions = NULL) {
  list(
    initialized = FALSE,
    protocol_version = NULL,
    client_initialized = FALSE,
    instructions = instructions,
    registry = as_tool_registry(tools)
  )
}

message_has_id <- function(message) {
  is.list(message) && "id" %in% names(message)
}

valid_message_id <- function(id) {
  is_string_id <- is_scalar_character(id)
  is_integer_id <- is.numeric(id) &&
    length(id) == 1 &&
    !is.na(id) &&
    is.finite(id) &&
    id == floor(id)

  is_string_id || is_integer_id
}

valid_request_message <- function(message) {
  is_named_list(message) &&
    identical(message$jsonrpc, "2.0") &&
    is_scalar_character(message$method) &&
    (!message_has_id(message) || valid_message_id(message$id))
}

is_required_string <- function(x) {
  is_scalar_character(x) && nzchar(x)
}

valid_client_info <- function(client_info) {
  is_named_list(client_info) &&
    is_required_string(client_info$name) &&
    is_required_string(client_info$version) &&
    (is.null(client_info$title) || is_required_string(client_info$title))
}

valid_initialize_params <- function(params) {
  is_named_list(params) &&
    is_required_string(params$protocolVersion) &&
    is_named_list(params$capabilities) &&
    valid_client_info(params$clientInfo)
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

  valid_meta <- !("_meta" %in% names(params)) ||
    (is.list(params$`_meta`) && length(params$`_meta`) == 0) ||
    is_named_list(params$`_meta`)

  valid_meta && (!("cursor" %in% names(params)) || is.null(params$cursor))
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
    if (message_has_id(message) && valid_message_id(message$id)) {
      id <- message$id
    }

    return(list(
      response = jsonrpc_invalid_request(id),
      state = state
    ))
  }

  # Activate for this dispatch frame so the complete valid operation stays
  # inside the span, including tool execution and all existing early returns.
  span <- start_mcp_server_span(message)
  result <- dispatch_valid_message(message, state)
  record_mcp_server_span_outcome(span, result$response, result$state)

  result
}

dispatch_valid_message <- function(message, state) {
  method <- message$method

  if (
    identical(method, "notifications/initialized") && message_has_id(message)
  ) {
    return(list(response = jsonrpc_invalid_request(message$id), state = state))
  }

  if (identical(method, "notifications/initialized")) {
    if (isTRUE(state$initialized)) {
      state$client_initialized <- TRUE
    }
    return(list(response = NULL, state = state))
  }

  # JSON-RPC notifications never receive responses, so only real requests
  # continue down the canonical initialize/dispatch path.
  if (!message_has_id(message)) {
    return(list(response = NULL, state = state))
  }

  id <- message$id

  if (identical(method, "initialize")) {
    return(handle_initialize_request(message, state))
  }

  if (identical(method, "ping")) {
    return(list(response = jsonrpc_response(id, named_list()), state = state))
  }

  if (!isTRUE(state$initialized)) {
    return(list(response = server_not_initialized_error(id), state = state))
  }

  if (identical(method, "tools/list")) {
    params <- message$params

    if (!valid_tools_list_params(params)) {
      return(list(response = jsonrpc_invalid_params(id), state = state))
    }

    return(list(
      response = jsonrpc_response(
        id,
        result = list(
          # The current registry always returns a single page; non-null cursors
          # are rejected at validation time instead of being silently ignored.
          tools = registry_tools_as_mcp(
            state$registry,
            state$protocol_version
          )
        )
      ),
      state = state
    ))
  }

  if (identical(method, "tools/call")) {
    return(handle_tool_call_request(message, state))
  }

  list(response = jsonrpc_method_not_found(id), state = state)
}

handle_initialize_request <- function(message, state) {
  params <- message$params
  id <- message$id

  if (!valid_initialize_params(params)) {
    return(list(
      response = jsonrpc_invalid_params(
        id,
        message = "Invalid initialize params"
      ),
      state = state
    ))
  }

  negotiated_version <- negotiate_protocol_version(params$protocolVersion)

  state$initialized <- TRUE
  state$protocol_version <- negotiated_version

  list(
    response = jsonrpc_response(
      id,
      result = server_capabilities(
        protocol_version = negotiated_version,
        instructions = state$instructions
      )
    ),
    state = state
  )
}

handle_tool_call_request <- function(message, state) {
  params <- message$params
  id <- message$id

  if (!is_named_list(params) || !is_scalar_character(params$name)) {
    return(list(response = jsonrpc_invalid_params(id), state = state))
  }

  if (!is.null(params$arguments) && !is_named_list(params$arguments)) {
    return(list(response = jsonrpc_invalid_params(id), state = state))
  }

  tool <- registry_tool(state$registry, params$name)

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
      params$arguments %||% named_list(),
      state$protocol_version
    ),
    state = state
  )
}
