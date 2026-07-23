supported_protocol_versions <- c(
  "2024-11-05",
  "2025-06-18",
  "2025-11-25"
)

latest_protocol_version <- supported_protocol_versions[
  length(supported_protocol_versions)
]

negotiate_protocol_version <- function(client_version) {
  if (
    is_scalar_character(client_version) &&
      client_version %in% supported_protocol_versions
  ) {
    client_version
  } else {
    latest_protocol_version
  }
}

protocol_version_gte <- function(version, reference) {
  version >= reference
}

jsonrpc_response <- function(id, result = NULL, error = NULL) {
  if (!xor(is.null(result), is.null(error))) {
    stop("Exactly one of `result` or `error` must be supplied.", call. = FALSE)
  }

  drop_nulls(list(
    jsonrpc = "2.0",
    id = id,
    result = result,
    error = error
  ))
}

jsonrpc_parse_error <- function() {
  jsonrpc_response(
    NULL,
    error = list(
      code = -32700,
      message = "Parse error"
    )
  )
}

jsonrpc_invalid_request <- function(id = NULL, message = "Invalid Request") {
  jsonrpc_response(
    id,
    error = list(
      code = -32600,
      message = message
    )
  )
}

jsonrpc_method_not_found <- function(id = NULL, message = "Method not found") {
  jsonrpc_response(
    id,
    error = list(
      code = -32601,
      message = message
    )
  )
}

jsonrpc_invalid_params <- function(id = NULL, message = "Invalid params") {
  jsonrpc_response(
    id,
    error = list(
      code = -32602,
      message = message
    )
  )
}

server_not_initialized_error <- function(id = NULL) {
  jsonrpc_invalid_request(id, message = "Server not initialized")
}

server_capabilities <- function(protocol_version, instructions = NULL) {
  out <- list(
    protocolVersion = protocol_version,
    capabilities = list(
      tools = named_list(
        listChanged = FALSE
      )
    ),
    serverInfo = list(
      name = "mcplite",
      version = package_version_string()
    )
  )

  if (
    protocol_version_gte(protocol_version, "2025-03-26") &&
      !is.null(instructions)
  ) {
    out$instructions <- instructions
  }

  out
}
