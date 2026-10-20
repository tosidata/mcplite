test_that("legacy and modern protocol versions have separate policies", {
  expect_identical(
    mcplite:::legacy_supported_protocol_versions,
    c("2024-11-05", "2025-06-18", "2025-11-25")
  )
  expect_identical(mcplite:::modern_supported_protocol_versions, "2026-07-28")
  expect_identical(
    mcplite:::discovery_supported_protocol_versions,
    c("2026-07-28", "2025-11-25", "2025-06-18", "2024-11-05")
  )
  expect_false("2025-03-26" %in% mcplite:::legacy_supported_protocol_versions)
})

test_that("legacy negotiation preserves all versions and latest fallback", {
  requested <- c(
    mcplite:::legacy_supported_protocol_versions,
    "9999-01-01",
    "2026-07-28"
  )
  expected <- c(
    mcplite:::legacy_supported_protocol_versions,
    rep("2025-11-25", 2)
  )

  for (index in seq_along(requested)) {
    initialized <- mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = requested[[index]]),
      new_test_state()
    )
    expect_identical(
      c(
        initialized$response$result$protocolVersion,
        initialized$state$legacy$protocol_version
      ),
      rep(expected[[index]], 2)
    )
  }
})

test_that("modern discovery is stateless, truthful, and cacheable", {
  instructions <- "Use the tools when needed."
  fresh <- new_test_state(instructions = instructions)
  initialized <- mcplite:::dispatch_message(
    legacy_initialize_request(protocol_version = "2025-06-18"),
    new_test_state(instructions = instructions)
  )
  notified <- mcplite:::dispatch_message(
    initialized_notification(),
    initialized$state
  )
  legacy_call <- mcplite:::dispatch_message(
    tool_call_request(name = "hello", arguments = list(name = "Ada")),
    notified$state
  )
  states <- list(fresh = fresh, post_legacy = legacy_call$state)

  for (state_name in names(states)) {
    state <- states[[state_name]]
    response <- mcplite:::dispatch_message(
      modern_discovery_request(id = paste0("discover-", state_name)),
      state
    )
    result <- response$response$result

    expect_identical(response$state, state, info = state_name)
    expect_identical(
      result$supportedVersions,
      as.list(mcplite:::discovery_supported_protocol_versions),
      info = state_name
    )
    expect_identical(
      result$capabilities,
      list(tools = named_list(listChanged = FALSE)),
      info = state_name
    )
    expect_identical(result$instructions, instructions, info = state_name)
    expect_identical(result$cacheScope, "public", info = state_name)
    expect_identical(result$ttlMs, 300000L, info = state_name)
    expect_identical(result$resultType, "complete", info = state_name)
    expect_identical(
      result$`_meta`[["io.modelcontextprotocol/serverInfo"]],
      state$config$server_info,
      info = state_name
    )
  }

  without_instructions <- mcplite:::dispatch_message(
    modern_discovery_request(),
    new_test_state()
  )
  expect_null(without_instructions$response$result$instructions)
})

test_that("modern lifecycle and excluded methods remain unsupported", {
  methods <- c("ping", "initialize", "resources/list", "prompts/list")
  states <- list(
    fresh = new_test_state(),
    post_legacy = mcplite:::dispatch_message(
      legacy_initialize_request(),
      new_test_state()
    )$state
  )

  for (state_name in names(states)) {
    state <- states[[state_name]]
    for (method in methods) {
      response <- mcplite:::dispatch_message(modern_request(method), state)
      expect_identical(response$response$error$code, -32601, info = method)
      expect_null(response$response$result, info = method)
      expect_identical(response$state, state, info = state_name)
    }
  }
})

test_that("request context isolates modern traffic from legacy lifecycle", {
  fresh <- new_test_state(instructions = "Use the tools when needed.")
  expect_named(fresh, c("config", "legacy"))
  expect_named(fresh$config, c("registry", "instructions", "server_info"))
  expect_named(
    fresh$legacy,
    c("initialized", "protocol_version", "client_initialized")
  )
  expect_null(fresh$initialized)
  expect_null(fresh$protocol_version)
  expect_null(fresh$client_initialized)

  initialized <- mcplite:::dispatch_message(
    legacy_initialize_request(protocol_version = "2025-06-18"),
    new_test_state(instructions = "Use the tools when needed.")
  )$state
  states <- list(fresh, initialized)

  valid <- modern_request(
    "tools/list",
    client_capabilities = named_list(
      "com.example/future" = named_list(enabled = TRUE)
    ),
    client_info = list(name = "", version = "", future = TRUE),
    extra_meta = named_list("com.example/request" = "kept")
  )

  missing_version <- modern_request("tools/list")
  missing_version$params$`_meta`[
    "io.modelcontextprotocol/protocolVersion"
  ] <- NULL
  missing_capabilities <- modern_request("tools/list")
  missing_capabilities$params$`_meta`[
    "io.modelcontextprotocol/clientCapabilities"
  ] <- NULL
  invalid_shape <- list(
    missing_version,
    modern_request("tools/list", protocol_version = 1),
    missing_capabilities,
    modern_request("tools/list", client_info = list(name = "client"))
  )

  for (before in states) {
    accepted <- mcplite:::dispatch_message(valid, before)
    expect_null(accepted$response$error)
    expect_identical(accepted$response$result$resultType, "complete")
    expect_identical(accepted$state, before)

    for (request in invalid_shape) {
      result <- mcplite:::dispatch_message(request, before)
      expect_identical(result$response$error$code, -32602)
      expect_identical(result$state, before)
    }

    for (unsupported in c("", "1900-01-01", "2025-11-25")) {
      request <- modern_request(
        "tools/list",
        protocol_version = unsupported,
        client_capabilities = "also invalid",
        client_info = list(name = "missing version")
      )
      result <- mcplite:::dispatch_message(request, before)
      expect_identical(result$response$error$code, -32022)
      expect_identical(result$response$error$data$requested, unsupported)
      expect_identical(
        result$response$error$data$supported,
        as.list(mcplite:::modern_supported_protocol_versions)
      )
      expect_identical(result$state, before)
    }

    discover <- mcplite:::dispatch_message(
      list(jsonrpc = "2.0", id = 11, method = "server/discover"),
      before
    )
    expect_identical(discover$response$error$code, -32602)
    expect_identical(discover$state, before)

    modern_ping <- mcplite:::dispatch_message(modern_request("ping"), before)
    expect_identical(modern_ping$response$error$code, -32601)
    expect_identical(modern_ping$state, before)

    modern_initialized <- modern_request("notifications/initialized")
    modern_initialized$id <- NULL
    notification <- mcplite:::dispatch_message(modern_initialized, before)
    expect_null(notification$response)
    expect_identical(notification$state, before)
  }

  for (state in states) {
    legacy_ping <- mcplite:::dispatch_message(
      list(jsonrpc = "2.0", id = 12, method = "ping"),
      state
    )
    expect_identical(legacy_ping$response$result, named_list())
    expect_identical(legacy_ping$state, state)
  }
})

test_that("modern-only log level metadata cannot downgrade to legacy", {
  for (state in list(
    new_test_state(),
    mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = "2025-06-18"),
      new_test_state()
    )$state
  )) {
    request <- list(
      jsonrpc = "2.0",
      id = 13,
      method = "tools/list",
      params = list(
        `_meta` = named_list(
          "io.modelcontextprotocol/logLevel" = "info"
        )
      )
    )
    result <- mcplite:::dispatch_message(request, state)

    expect_identical(result$response$error$code, -32602)
    expect_identical(result$state, state)
  }
})

test_that("modern request log levels follow the final enum", {
  valid_levels <- c(
    "alert",
    "critical",
    "debug",
    "emergency",
    "error",
    "info",
    "notice",
    "warning"
  )
  malformed_levels <- list(
    numeric = 1,
    logical = TRUE,
    null = NULL,
    list = list("info"),
    unknown_string = "verbose",
    multi_value = c("info", "warning")
  )
  states <- list(
    fresh = new_test_state(),
    post_legacy = mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = "2025-06-18"),
      new_test_state()
    )$state
  )
  log_level_key <- "io.modelcontextprotocol/logLevel"

  expect_identical(mcplite:::modern_logging_levels, valid_levels)

  for (state_name in names(states)) {
    state <- states[[state_name]]

    for (level in valid_levels) {
      extra_meta <- named_list("com.example/request" = "kept")
      extra_meta[[log_level_key]] <- level
      request <- modern_request(
        "tools/list",
        client_capabilities = named_list(
          "com.example/future" = named_list(enabled = TRUE)
        ),
        extra_meta = extra_meta
      )
      result <- mcplite:::dispatch_message(request, state)
      info <- paste(state_name, level, sep = ": ")

      expect_null(result$response$error, info = info)
      expect_identical(
        result$response$result$resultType,
        "complete",
        info = info
      )
      expect_identical(result$state, state, info = info)
    }

    for (case_name in names(malformed_levels)) {
      extra_meta <- named_list("com.example/request" = "kept")
      extra_meta[log_level_key] <- list(malformed_levels[[case_name]])
      request <- modern_request(
        "tools/list",
        client_capabilities = named_list(
          "com.example/future" = named_list(enabled = TRUE)
        ),
        extra_meta = extra_meta
      )
      result <- mcplite:::dispatch_message(request, state)
      info <- paste(state_name, case_name, sep = ": ")

      expect_identical(result$response$error$code, -32602, info = info)
      expect_identical(result$state, state, info = info)
    }
  }
})

test_that("shared request metadata alone remains legacy", {
  states <- list(
    new_test_state(),
    mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = "2025-06-18"),
      new_test_state()
    )$state
  )
  shared_meta <- list(
    traceparent = "00-invalid",
    tracestate = "vendor=value",
    progressToken = 1L
  )

  for (state in states) {
    for (key in names(shared_meta)) {
      request <- list(
        jsonrpc = "2.0",
        id = 14,
        method = "ping",
        params = list(
          `_meta` = stats::setNames(list(shared_meta[[key]]), key)
        )
      )
      result <- mcplite:::dispatch_message(request, state)

      expect_identical(result$response$result, named_list())
      expect_identical(result$state, state)
    }
  }
})

test_that("modern request metadata uses exact reserved wire keys", {
  keys <- mcplite:::modern_metadata_keys
  states <- list(
    fresh = new_test_state(),
    post_legacy = mcplite:::dispatch_message(
      legacy_initialize_request(protocol_version = "2025-06-18"),
      new_test_state()
    )$state
  )

  version_prefix <- modern_request("tools/list")
  version_prefix$params[["_meta"]][keys[["protocol_version"]]] <- NULL
  version_prefix$params[["_meta"]][[
    paste0(keys[["protocol_version"]], "Extra")
  ]] <- "2026-07-28"

  capabilities_prefix <- modern_request("tools/list")
  capabilities_prefix$params[["_meta"]][keys[["client_capabilities"]]] <- NULL
  capabilities_prefix$params[["_meta"]][[
    paste0(keys[["client_capabilities"]], "Extra")
  ]] <- "not-an-object"

  client_name_prefix <- modern_request(
    "tools/list",
    client_info = list(nameExtension = "client", version = "1.0")
  )
  client_version_prefix <- modern_request(
    "tools/list",
    client_info = list(name = "client", versionExtension = "1.0")
  )

  meta_prefix <- modern_discovery_request()
  names(meta_prefix$params)[names(meta_prefix$params) == "_meta"] <-
    "_metaExtra"

  malformed <- list(
    protocol_version_prefix = version_prefix,
    client_capabilities_prefix = capabilities_prefix,
    client_name_prefix = client_name_prefix,
    client_version_prefix = client_version_prefix,
    meta_prefix = meta_prefix
  )

  for (state_name in names(states)) {
    state <- states[[state_name]]
    for (case_name in names(malformed)) {
      result <- mcplite:::dispatch_message(malformed[[case_name]], state)
      info <- paste(state_name, case_name, sep = ": ")

      expect_identical(result$response$error$code, -32602, info = info)
      expect_identical(result$state, state, info = info)
    }

    optional_prefixes <- named_list(
      "io.modelcontextprotocol/clientInfoExtra" = list(
        nameExtension = "not-standard",
        versionExtension = "not-standard"
      ),
      "io.modelcontextprotocol/logLevelExtra" = "verbose"
    )
    accepted <- mcplite:::dispatch_message(
      modern_request("tools/list", extra_meta = optional_prefixes),
      state
    )

    expect_null(accepted$response$error, info = state_name)
    expect_identical(accepted$state, state, info = state_name)
  }
})

test_that("modern result decorator covers every successful seam shape", {
  state <- new_test_state()
  context <- mcplite:::build_request_context(
    modern_request("ping"),
    state
  )$context
  decorate <- function(response) {
    mcplite:::decorate_modern_result(
      response,
      context,
      state$config$server_info
    )
  }
  expect_canonical_fields <- function(response) {
    expect_identical(response$result$resultType, "complete")
    expect_identical(
      response$result$`_meta`[["io.modelcontextprotocol/serverInfo"]],
      state$config$server_info
    )
  }

  ordinary <- mcplite:::jsonrpc_response(
    1,
    result = list(tools = list())
  )
  decorated_ordinary <- decorate(ordinary)
  expect_canonical_fields(decorated_ordinary)
  expect_identical(decorated_ordinary$result$tools, list())

  tool_error <- mcplite:::jsonrpc_response(
    2,
    result = list(
      content = list(list(type = "text", text = "Domain error")),
      structuredContent = list(ok = FALSE),
      isError = TRUE
    )
  )
  decorated_tool_error <- decorate(tool_error)
  expect_canonical_fields(decorated_tool_error)
  expect_true(decorated_tool_error$result$isError)
  expect_identical(
    decorated_tool_error$result$structuredContent,
    list(ok = FALSE)
  )

  fallback <- mcplite:::jsonrpc_response(
    3,
    result = list(
      content = list(list(type = "text", text = "Normalization failed")),
      isError = TRUE
    )
  )
  decorated_fallback <- decorate(fallback)
  expect_canonical_fields(decorated_fallback)
  expect_identical(
    decorated_fallback$result$content,
    fallback$result$content
  )
  expect_true(decorated_fallback$result$isError)

  malformed_meta <- mcplite:::jsonrpc_response(
    4,
    result = list(`_meta` = "spoofed")
  )
  decorated_malformed <- decorate(malformed_meta)
  expect_canonical_fields(decorated_malformed)
  expect_named(
    decorated_malformed$result$`_meta`,
    "io.modelcontextprotocol/serverInfo"
  )

  spoofed_meta <- mcplite:::jsonrpc_response(
    5,
    result = list(
      resultType = "spoofed",
      `_meta` = named_list(
        "io.modelcontextprotocol/serverInfo" = list(name = "spoofed"),
        "com.example/result" = TRUE
      )
    )
  )
  decorated_spoofed <- decorate(spoofed_meta)
  expect_canonical_fields(decorated_spoofed)
  expect_true(decorated_spoofed$result$`_meta`[["com.example/result"]])

  jsonrpc_error <- mcplite:::jsonrpc_method_not_found(6)
  expect_identical(decorate(jsonrpc_error), jsonrpc_error)
  notification <- NULL
  expect_null(decorate(notification))
})

test_that("modern and legacy projection policies have distinct seams", {
  modern <- mcplite:::build_request_context(
    modern_request("ping"),
    new_test_state()
  )$context
  current_legacy <- mcplite:::build_request_context(
    legacy_initialize_request(),
    new_test_state()
  )$context
  old_legacy <- mcplite:::build_request_context(
    legacy_initialize_request(protocol_version = "2024-11-05"),
    new_test_state()
  )$context

  input <- mcplite:::input_schema_projection_policy
  output <- mcplite:::output_schema_projection_policy
  structured <- mcplite:::structured_content_projection_policy

  expect_identical(
    c(input(modern), input(current_legacy), input(old_legacy)),
    rep("object-root", 3)
  )
  expect_identical(
    c(output(modern), output(current_legacy), output(old_legacy)),
    c("any-json-schema", "object-root", "omit")
  )
  expect_identical(
    c(structured(modern), structured(current_legacy), structured(old_legacy)),
    c("any-json-value", "object-value", "omit")
  )
})

test_that("initialize returns truthful capabilities and protocol-aware instructions", {
  state <- new_test_state(instructions = "Use the tools when needed.")

  initialized <- mcplite:::dispatch_message(
    legacy_initialize_request(protocol_version = "2024-11-05"),
    state
  )

  expect_true(initialized$state$legacy$initialized)
  expect_named(initialized$response$result$capabilities, "tools")
  expect_null(initialized$response$result$capabilities$prompts)
  expect_null(initialized$response$result$capabilities$resources)
  expect_null(initialized$response$result$instructions)

  newer <- mcplite:::dispatch_message(
    legacy_initialize_request(protocol_version = "2025-11-25"),
    new_test_state(instructions = "Use the tools when needed.")
  )

  expect_identical(
    newer$response$result$instructions,
    "Use the tools when needed."
  )
})

test_that("non-lifecycle requests are rejected before initialize", {
  response <- mcplite:::dispatch_message(tools_list_request(), new_test_state())

  expect_identical(response$response$error$code, -32600)
  expect_match(response$response$error$message, "not initialized")
})

test_that("initialized notification before initialize leaves state unchanged", {
  result <- mcplite:::dispatch_message(
    initialized_notification(),
    new_test_state()
  )

  expect_null(result$response)
  expect_false(result$state$legacy$initialized)
  expect_false(result$state$legacy$client_initialized)
})

test_that("initialized notification with an id returns an error", {
  before_initialize <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "notifications/initialized"),
    new_test_state()
  )

  expect_identical(before_initialize$response$error$code, -32600)
  expect_identical(before_initialize$response$id, 1)
  expect_false(before_initialize$state$legacy$initialized)
  expect_false(before_initialize$state$legacy$client_initialized)

  state <- mcplite:::dispatch_message(
    legacy_initialize_request(),
    new_test_state()
  )$state

  after_initialize <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 2, method = "notifications/initialized"),
    state
  )

  expect_identical(after_initialize$response$error$code, -32600)
  expect_identical(after_initialize$response$id, 2)
  expect_true(after_initialize$state$legacy$initialized)
  expect_false(after_initialize$state$legacy$client_initialized)
})

test_that("valid initialized notifications remain no-response notifications", {
  state <- mcplite:::dispatch_message(
    legacy_initialize_request(),
    new_test_state()
  )$state

  result <- mcplite:::dispatch_message(
    initialized_notification(),
    state
  )

  expect_null(result$response)
  expect_true(result$state$legacy$initialized)
  expect_true(result$state$legacy$client_initialized)
})

test_that("ping succeeds before initialize", {
  response <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 99, method = "ping"),
    new_test_state()
  )

  expect_identical(response$response$result, named_list())
})

test_that("unknown methods return JSON-RPC method not found errors", {
  state <- mcplite:::dispatch_message(
    legacy_initialize_request(),
    new_test_state()
  )$state

  response <- mcplite:::dispatch_message(
    list(jsonrpc = "2.0", id = 10, method = "resources/list"),
    state
  )

  expect_identical(response$response$error$code, -32601)
})

test_that("JSON-RPC envelope keys require exact wire names", {
  state <- new_test_state()
  invalid_envelopes <- list(
    jsonrpc_prefix = list(
      jsonrpcExtra = "2.0",
      id = 1,
      method = "ping"
    ),
    method_prefix = list(
      jsonrpc = "2.0",
      id = 2,
      methodExtra = "ping"
    ),
    notification_method_prefix = list(
      jsonrpc = "2.0",
      methodExtra = "notifications/initialized"
    )
  )

  for (case_name in names(invalid_envelopes)) {
    result <- mcplite:::dispatch_message(
      invalid_envelopes[[case_name]],
      state
    )
    expect_identical(
      result$response$error$code,
      -32600,
      info = case_name
    )
    expect_identical(result$state, state, info = case_name)
  }

  id_prefix <- legacy_initialize_request(id = 3)
  names(id_prefix)[names(id_prefix) == "id"] <- "idExtra"
  notification <- mcplite:::dispatch_message(id_prefix, state)

  expect_null(notification$response)
  expect_identical(notification$state, state)
})

test_that("legacy initialize maps require exact params and identity keys", {
  valid_params <- legacy_initialize_request()$params
  prefixed <- list(
    params = list(
      paramsExtra = valid_params
    ),
    protocol_version = list(
      params = list(
        protocolVersionExtra = "2025-06-18",
        capabilities = named_list(),
        clientInfo = list(name = "client", version = "1.0")
      )
    ),
    capabilities = list(
      params = list(
        protocolVersion = "2025-06-18",
        capabilitiesExtra = named_list(),
        clientInfo = list(name = "client", version = "1.0")
      )
    ),
    client_info = list(
      params = list(
        protocolVersion = "2025-06-18",
        capabilities = named_list(),
        clientInfoExtra = list(name = "client", version = "1.0")
      )
    ),
    client_name = list(
      params = list(
        protocolVersion = "2025-06-18",
        capabilities = named_list(),
        clientInfo = list(nameExtension = "client", version = "1.0")
      )
    ),
    client_version = list(
      params = list(
        protocolVersion = "2025-06-18",
        capabilities = named_list(),
        clientInfo = list(name = "client", versionExtension = "1.0")
      )
    )
  )

  for (case_name in names(prefixed)) {
    request <- c(
      list(jsonrpc = "2.0", id = 20, method = "initialize"),
      prefixed[[case_name]]
    )
    state <- new_test_state()
    result <- mcplite:::dispatch_message(request, state)

    expect_identical(result$response$error$code, -32602, info = case_name)
    expect_identical(result$state, state, info = case_name)
  }
})

test_that("malformed JSON-RPC envelopes are rejected", {
  missing_jsonrpc <- mcplite:::dispatch_message(
    list(
      id = 1,
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_identical(missing_jsonrpc$response$error$code, -32600)
  expect_false(missing_jsonrpc$state$legacy$initialized)

  invalid_jsonrpc <- mcplite:::dispatch_message(
    list(
      jsonrpc = "1.0",
      id = 1,
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_identical(invalid_jsonrpc$response$error$code, -32600)
  expect_false(invalid_jsonrpc$state$legacy$initialized)

  batch_like <- mcplite:::dispatch_message(
    list(legacy_initialize_request()),
    new_test_state()
  )
  expect_identical(batch_like$response$error$code, -32600)
})

test_that("invalid JSON-RPC ids are rejected at the request boundary", {
  invalid_ids <- list(
    NULL,
    TRUE,
    1.5,
    Inf,
    NA_real_,
    c(1, 2),
    list("bad"),
    named_list(bad = "shape")
  )

  for (bad_id in invalid_ids) {
    response <- mcplite:::dispatch_message(
      list(
        jsonrpc = "2.0",
        id = bad_id,
        method = "initialize",
        params = list(protocolVersion = "2025-11-25")
      ),
      new_test_state()
    )

    expect_identical(response$response$error$code, -32600)
    expect_false(response$state$legacy$initialized)
    expect_null(response$response$id)
  }
})

test_that("string and integer JSON-RPC ids remain valid", {
  string_id <- mcplite:::dispatch_message(
    legacy_initialize_request(id = "request-1"),
    new_test_state()
  )
  expect_true(string_id$state$legacy$initialized)
  expect_identical(string_id$response$id, "request-1")

  integer_id <- mcplite:::dispatch_message(
    legacy_initialize_request(id = 1L),
    new_test_state()
  )
  expect_true(integer_id$state$legacy$initialized)
  expect_identical(integer_id$response$id, 1L)
})

test_that("notifications stay distinct from explicit null request ids", {
  initialize_notification <- mcplite:::dispatch_message(
    list(
      jsonrpc = "2.0",
      method = "initialize",
      params = list(protocolVersion = "2025-11-25")
    ),
    new_test_state()
  )
  expect_null(initialize_notification$response)
  expect_false(initialize_notification$state$legacy$initialized)

  initialize_request_with_null_id <- mcplite:::dispatch_message(
    legacy_initialize_request(id = NULL),
    new_test_state()
  )
  expect_identical(initialize_request_with_null_id$response$error$code, -32600)
  expect_false(initialize_request_with_null_id$state$legacy$initialized)
  expect_null(initialize_request_with_null_id$response$id)
})

test_that("malformed initialize requests use the invalid params path", {
  invalid_params <- list(
    named_list(),
    list(protocolVersion = 1),
    list(
      protocolVersion = "2025-11-25",
      clientInfo = list(name = "mcplite-tests", version = "0.0.0")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = list(),
      clientInfo = list(name = "mcplite-tests", version = "0.0.0")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = named_list(),
      clientInfo = list(name = "mcplite-tests")
    ),
    list(
      protocolVersion = "2025-11-25",
      capabilities = named_list(),
      clientInfo = list(name = 1, version = "0.0.0")
    )
  )

  for (params in invalid_params) {
    state <- new_test_state()
    response <- mcplite:::dispatch_message(
      list(
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
        params = params
      ),
      state
    )

    expect_identical(response$response$error$code, -32602)
    expect_false(response$state$legacy$initialized)
    expect_null(response$state$legacy$protocol_version)
    expect_false(response$state$legacy$client_initialized)
  }
})

test_that("malformed JSON returns a parse error", {
  response <- mcplite:::handle_input_line("{not-json}", new_test_state())

  expect_identical(response$response$error$code, -32700)
})
