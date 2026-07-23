normalize_tool_arguments <- function(arguments) {
  if (is.null(arguments)) {
    return(named_list())
  }

  # Preserve parsed JSON arrays and objects exactly as received so tool code can
  # distinguish nested arrays from flattened atomic values.
  arguments
}

invoke_tool <- function(tool, arguments) {
  utils::capture.output(
    value <- do.call(tool, normalize_tool_arguments(arguments)),
    type = "output"
  )

  value
}

execute_tool_call <- function(id, tool, arguments, protocol_version) {
  result <- tryCatch(
    invoke_tool(tool, arguments),
    error = function(cnd) {
      new_text_tool_result(
        conditionMessage(cnd),
        is_error = TRUE
      )
    }
  )

  tryCatch(
    as_tool_call_response(id, result, protocol_version),
    error = function(cnd) {
      # This fallback is intentionally one known-good text block and does not
      # recurse through the failed result normalization path.
      error_result <- new_text_tool_result(
        conditionMessage(cnd),
        is_error = TRUE
      )
      jsonrpc_response(
        id,
        result = tool_result_as_mcp(error_result, protocol_version)
      )
    }
  )
}
