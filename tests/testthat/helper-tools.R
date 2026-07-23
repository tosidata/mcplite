initialize_request <- function(id = 1, protocol_version = "2025-11-25") {
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
