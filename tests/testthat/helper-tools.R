legacy_initialize_request <- function(id = 1, protocol_version = "2025-11-25") {
  list(
    jsonrpc = "2.0",
    id = id,
    method = "initialize",
    params = list(
      protocolVersion = protocol_version,
      capabilities = named_list(),
      clientInfo = list(
        name = "mcplite-tests",
        version = "0.0.0"
      )
    )
  )
}

# Preserve established legacy blocks while mixed-era tests name the era.
initialize_request <- legacy_initialize_request

modern_request <- function(
  method,
  id = 1,
  protocol_version = "2026-07-28",
  client_capabilities = named_list(),
  client_info = NULL,
  params = named_list(),
  extra_meta = named_list()
) {
  meta <- named_list(
    "io.modelcontextprotocol/protocolVersion" = protocol_version,
    "io.modelcontextprotocol/clientCapabilities" = client_capabilities
  )
  meta <- c(meta, extra_meta)

  if (!is.null(client_info)) {
    meta[["io.modelcontextprotocol/clientInfo"]] <- client_info
  }
  params[["_meta"]] <- meta

  list(
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params
  )
}

modern_discovery_request <- function(id = 1, ...) {
  modern_request("server/discover", id = id, ...)
}

modern_tools_list_request <- function(id = 2, ...) {
  modern_request("tools/list", id = id, ...)
}

modern_tool_call_request <- function(
  id = 3,
  name,
  arguments = named_list(),
  ...
) {
  params <- list(name = name)
  if (length(arguments) > 0) {
    params$arguments <- arguments
  }

  modern_request("tools/call", id = id, params = params, ...)
}

initialized_notification <- function() {
  list(
    jsonrpc = "2.0",
    method = "notifications/initialized"
  )
}

tools_list_request <- function(id = 2, params = NULL) {
  request <- list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/list"
  )

  if (!is.null(params)) {
    request$params <- params
  }

  request
}

tool_call_request <- function(id = 3, name, arguments = named_list()) {
  params <- list(name = name)

  if (length(arguments) > 0) {
    params$arguments <- arguments
  }

  list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/call",
    params = params
  )
}

sample_tools <- function() {
  list(
    mcplite::tool(
      function() {
        "ready"
      },
      name = "status",
      description = "Return a simple readiness string."
    ),
    mcplite::tool(
      function(name) {
        sprintf("Hello, %s!", name)
      },
      name = "hello",
      description = "Say hello to a person.",
      arguments = list(
        name = mcplite::type_string("Name to greet.")
      )
    ),
    mcplite::tool(
      function() {
        stop("boom", call. = FALSE)
      },
      name = "explode",
      description = "Fail deliberately."
    ),
    mcplite::tool(
      function() {
        cat("tool output should not reach stdout\n")
        "quiet"
      },
      name = "chatty",
      description = "Write to stdout before returning."
    )
  )
}

new_test_state <- function(instructions = NULL) {
  mcplite:::new_server_state(sample_tools(), instructions = instructions)
}
