start_mcp_server_span <- function(
  message,
  activation_scope = parent.frame()
) {
  if (!otel::is_tracing_enabled()) {
    return(NULL)
  }

  method <- message$method
  params <- message$params
  span_name <- method
  tool_name <- if (is.list(params)) params$name

  attributes <- list(
    "mcp.method.name" = method,
    "network.transport" = "pipe"
  )

  if (identical(method, "tools/call")) {
    attributes[["gen_ai.operation.name"]] <- "execute_tool"
    if (is_scalar_character(tool_name)) {
      attributes[["gen_ai.tool.name"]] <- tool_name
      span_name <- paste(method, tool_name)
    }
  }

  if (!is.null(message$id)) {
    attributes[["jsonrpc.request.id"]] <- as.character(message$id)
  }

  options <- list(kind = "server")

  if (is.list(params) && !is.null(meta <- params[["_meta"]])) {
    # Invalid propagation metadata is absent at the MCP boundary; only a
    # valid extracted context may override normal ambient parent selection.
    tryCatch(
      {
        traceparent <- meta[["traceparent"]]
        if (!is.null(traceparent) && is_scalar_character(traceparent)) {
          headers <- list(traceparent = traceparent)
          tracestate <- meta[["tracestate"]]
          if (is.null(tracestate) || is_scalar_character(tracestate)) {
            headers$tracestate <- tracestate
            context <- otel::extract_http_context(headers)
            if (context$is_valid()) {
              options$parent <- context
            }
          }
        }
      },
      error = function(cnd) NULL
    )
  }

  otel::start_local_active_span(
    name = span_name,
    attributes = attributes,
    options = options,
    activation_scope = activation_scope
  )
}

record_mcp_server_span_outcome <- function(span, response, state) {
  if (is.null(span) || !isTRUE(span$is_recording())) {
    return(invisible(NULL))
  }

  protocol_version <- state$protocol_version
  if (
    is.character(protocol_version) &&
      length(protocol_version) == 1L &&
      !is.na(protocol_version)
  ) {
    span$set_attribute("mcp.protocol.version", protocol_version)
  }

  if (!is.null(response$error)) {
    error_type <- as.character(response$error$code)
    span$set_attribute("error.type", error_type)
    span$set_attribute("rpc.response.status_code", error_type)
    span$set_status("error")
  } else if (isTRUE(response$result$isError)) {
    span$set_attribute("error.type", "tool_error")
    span$set_status("error")
  }

  invisible(NULL)
}
