read_output_lines_until <- function(process, n, timeout = 3) {
  deadline <- Sys.time() + timeout
  lines <- character()

  while (length(lines) < n && Sys.time() < deadline) {
    processx::poll(list(process), 100)
    lines <- c(lines, process$read_output_lines())
  }

  lines
}

read_stdio_response <- function(process, timeout = 3) {
  lines <- read_output_lines_until(process, 1, timeout = timeout)
  expect_length(lines, 1)

  jsonlite::parse_json(lines[[1]], simplifyVector = FALSE)
}

expect_jsonrpc_error <- function(response, id, code) {
  expect_equal(response$id, id)
  expect_equal(response$error$code, code)
  expect_null(response$result)
}

stdio_server_script <- function(mode = c("source", "installed")) {
  mode <- match.arg(mode)

  libpaths <- paste(capture.output(dput(.libPaths())), collapse = "")
  source_root <- normalizePath(
    test_path("..", ".."),
    winslash = "/",
    mustWork = TRUE
  )

  script <- c(sprintf(".libPaths(%s)", libpaths))

  if (identical(mode, "source")) {
    script <- c(
      script,
      sprintf("source_root <- %s", encodeString(source_root, quote = '"')),
      "parse_json <- jsonlite::parse_json",
      "toJSON <- jsonlite::toJSON",
      "for (path in sort(list.files(file.path(source_root, 'R'), full.names = TRUE, pattern = '\\\\.R$'))) {",
      "  sys.source(path, envir = globalenv())",
      "}",
      "run_server <- mcp_server",
      "run_tool <- tool",
      "run_result <- tool_result",
      "run_content_text <- content_text",
      "run_content_image <- content_image",
      "run_content_audio <- content_audio",
      "run_content_resource <- content_resource"
    )
  }

  if (identical(mode, "installed")) {
    script <- c(
      script,
      "package_root <- normalizePath(find.package('mcplite'), winslash = '/', mustWork = TRUE)",
      "if (!grepl('.Rcheck', package_root, fixed = TRUE)) stop('Expected check-stage mcplite installation.')",
      "run_server <- mcplite::mcp_server",
      "run_tool <- mcplite::tool",
      "run_result <- mcplite::tool_result",
      "run_content_text <- mcplite::content_text",
      "run_content_image <- mcplite::content_image",
      "run_content_audio <- mcplite::content_audio",
      "run_content_resource <- mcplite::content_resource"
    )
  }

  c(
    script,
    "chatty_tool <- run_tool(",
    "  function() { cat('tool output should not reach stdout\\n'); 'quiet' },",
    "  name = 'chatty',",
    "  description = 'Write to stdout before returning.'",
    ")",
    "explode_tool <- run_tool(",
    "  function() { stop('test tool failure', call. = FALSE) },",
    "  name = 'explode',",
    "  description = 'Always fails for error recovery tests.'",
    ")",
    "rich_tool <- run_tool(",
    "  function() {",
    "    cat('rich tool output should not reach stdout\\n')",
    "    run_result(",
    "      content = list(",
    "        run_content_text('first'),",
    "        run_content_image('aW1hZ2U=', 'image/png'),",
    "        run_content_resource('urn:stdio:text', text = 'body', mime_type = 'text/plain')",
    "      ),",
    "      structured_content = list(ok = TRUE, values = list(1L, 2L)),",
    "      meta = list(trace_id = 'stdio')",
    "    )",
    "  },",
    "  name = 'rich',",
    "  description = 'Return mixed protocol-native content.'",
    ")",
    "audio_tool <- run_tool(",
    "  function() run_result(run_content_audio('YXVkaW8=', 'audio/wav')),",
    "  name = 'audio',",
    "  description = 'Return audio for protocol-gating tests.'",
    ")",
    "run_server(list(chatty_tool, explode_tool, rich_tool, audio_tool))"
  )
}

start_stdio_process <- function(
  mode = c("source", "installed"),
  process_env = NULL,
  env = parent.frame()
) {
  mode <- match.arg(mode)
  script <- withr::local_tempfile(fileext = ".R", .local_envir = env)
  writeLines(stdio_server_script(mode), script)

  processx::process$new(
    command = file.path(R.home("bin"), "Rscript"),
    args = c("--vanilla", script),
    stdin = "|",
    stdout = "|",
    stderr = "|",
    env = process_env
  )
}

stdio_client_messages <- function() {
  # Check-stage installed tests cannot rely on unexported package helpers.
  empty_object <- structure(list(), names = character())
  encode <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")

  list(
    malformed_json = "{not-json}",
    initialize = encode(list(
      jsonrpc = "2.0",
      id = 1,
      method = "initialize",
      params = list(
        protocolVersion = "2025-11-25",
        capabilities = empty_object,
        clientInfo = list(
          name = "mcplite-tests",
          version = "0.0.0"
        )
      )
    )),
    initialize_old = encode(list(
      jsonrpc = "2.0",
      id = 1,
      method = "initialize",
      params = list(
        protocolVersion = "2024-11-05",
        capabilities = empty_object,
        clientInfo = list(
          name = "mcplite-tests",
          version = "0.0.0"
        )
      )
    )),
    initialized = encode(list(
      jsonrpc = "2.0",
      method = "notifications/initialized"
    )),
    unknown_method = encode(list(
      jsonrpc = "2.0",
      id = 2,
      method = "unknown/method"
    )),
    tool_call = encode(list(
      jsonrpc = "2.0",
      id = 3,
      method = "tools/call",
      params = list(name = "chatty")
    )),
    unknown_tool_call = encode(list(
      jsonrpc = "2.0",
      id = 4,
      method = "tools/call",
      params = list(name = "missing")
    )),
    exploding_tool_call = encode(list(
      jsonrpc = "2.0",
      id = 5,
      method = "tools/call",
      params = list(name = "explode")
    )),
    recovery_tool_call = encode(list(
      jsonrpc = "2.0",
      id = 6,
      method = "tools/call",
      params = list(name = "chatty")
    )),
    rich_tool_call = encode(list(
      jsonrpc = "2.0",
      id = 7,
      method = "tools/call",
      params = list(name = "rich")
    )),
    audio_tool_call = encode(list(
      jsonrpc = "2.0",
      id = 8,
      method = "tools/call",
      params = list(name = "audio")
    ))
  )
}

run_stdio_roundtrip <- function(mode = c("source", "installed")) {
  process <- start_stdio_process(mode)
  withr::defer(process$kill())
  messages <- stdio_client_messages()

  process$write_input(paste0(messages$initialize, "\n"))
  initialize_response <- read_output_lines_until(process, 1)

  process$write_input(paste0(messages$initialized, "\n"))
  process$write_input(paste0(messages$tool_call, "\n"))
  tool_response <- read_output_lines_until(process, 1)

  list(
    initialize_response = initialize_response,
    tool_response = tool_response,
    stderr_lines = process$read_error_lines()
  )
}

expect_stdio_roundtrip <- function(roundtrip) {
  expect_length(roundtrip$initialize_response, 1)
  expect_length(roundtrip$tool_response, 1)
  expect_length(roundtrip$stderr_lines, 0)

  initialize_json <- jsonlite::parse_json(
    roundtrip$initialize_response[[1]],
    simplifyVector = FALSE
  )
  tool_json <- jsonlite::parse_json(
    roundtrip$tool_response[[1]],
    simplifyVector = FALSE
  )

  expect_identical(initialize_json$result$capabilities$tools$listChanged, FALSE)
  expect_identical(tool_json$result$content[[1]]$text, "quiet")
}

test_that("stdio server keeps stdout reserved for MCP JSON messages in source tests", {
  skip_if_not_installed("processx")
  skip_if(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  expect_stdio_roundtrip(run_stdio_roundtrip("source"))
})

test_that("stdio keeps stderr telemetry separate from MCP stdout", {
  skip_if_not_installed("processx")
  skip_if_not_installed("otelsdk")
  # Check-stage subprocesses must exercise the installed package,
  # rather than sourced R/ files.
  skip_if(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  process <- start_stdio_process(
    "source",
    process_env = c(
      "current",
      OTEL_TRACES_EXPORTER = "none",
      OTEL_R_TRACES_EXPORTER = "stderr",
      OTEL_SDK_DISABLED = "false",
      OTEL_R_EMIT_SCOPES = "",
      OTEL_R_SUPPRESS_SCOPES = "",
      OTEL_R_EXPORTER_STDSTREAM_OUTPUT = "stderr",
      OTEL_R_EXPORTER_STDSTREAM_TRACES_OUTPUT = "stderr"
    )
  )
  withr::defer(process$kill())

  process$write_input(paste0(stdio_client_messages()$initialize, "\n"))
  stdout_lines <- read_output_lines_until(process, 1)
  close(process$get_input_connection())

  deadline <- Sys.time() + 3
  while (process$is_alive() && Sys.time() < deadline) {
    processx::poll(list(process), 100)
  }

  expect_false(process$is_alive())
  if (process$is_alive()) {
    process$kill()
  }

  stdout_lines <- c(stdout_lines, process$read_all_output_lines())
  stderr_lines <- process$read_all_error_lines()
  stderr_output <- paste(stderr_lines, collapse = "\n")

  expect_identical(process$get_exit_status(), 0L)
  expect_length(stdout_lines, 1L)
  stdout_response <- jsonlite::parse_json(
    stdout_lines[[1]],
    simplifyVector = FALSE
  )
  expect_equal(
    stdout_response,
    list(
      jsonrpc = "2.0",
      id = 1L,
      result = list(
        protocolVersion = "2025-11-25",
        capabilities = list(tools = list(listChanged = FALSE)),
        serverInfo = list(
          name = "mcplite",
          version = as.character(
            utils::packageVersion("mcplite", lib.loc = .libPaths())
          )
        )
      )
    )
  )
  expect_true(nzchar(stderr_output))
  expect_match(stderr_output, "mcp.method.name", fixed = TRUE)
  expect_match(stderr_output, "initialize", fixed = TRUE)
})

test_that("stdio server recovers from live JSON-RPC errors in source tests", {
  skip_if_not_installed("processx")
  skip_if(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  process <- start_stdio_process("source")
  withr::defer(process$kill())
  messages <- stdio_client_messages()

  process$write_input(paste0(messages$malformed_json, "\n"))
  parse_error <- read_stdio_response(process)
  expect_jsonrpc_error(parse_error, NULL, -32700)

  process$write_input(paste0(messages$initialize, "\n"))
  initialize_response <- read_stdio_response(process)
  expect_equal(initialize_response$id, 1)
  expect_identical(
    initialize_response$result$capabilities$tools$listChanged,
    FALSE
  )
  expect_null(initialize_response$error)

  process$write_input(paste0(messages$initialized, "\n"))

  process$write_input(paste0(messages$unknown_method, "\n"))
  unknown_method <- read_stdio_response(process)
  expect_jsonrpc_error(unknown_method, 2, -32601)

  process$write_input(paste0(messages$unknown_tool_call, "\n"))
  unknown_tool <- read_stdio_response(process)
  expect_jsonrpc_error(unknown_tool, 4, -32602)

  process$write_input(paste0(messages$tool_call, "\n"))
  tool_response <- read_stdio_response(process)
  expect_equal(tool_response$id, 3)
  expect_identical(tool_response$result$content[[1]]$text, "quiet")
  expect_false(tool_response$result$isError)
  expect_null(tool_response$error)

  process$write_input(paste0(messages$exploding_tool_call, "\n"))
  exploding_tool <- read_stdio_response(process)
  expect_equal(exploding_tool$id, 5)
  expect_true(exploding_tool$result$isError)
  expect_type(exploding_tool$result$content[[1]]$text, "character")
  expect_null(exploding_tool$error)

  process$write_input(paste0(messages$recovery_tool_call, "\n"))
  recovery_tool <- read_stdio_response(process)
  expect_equal(recovery_tool$id, 6)
  expect_identical(recovery_tool$result$content[[1]]$text, "quiet")
  expect_false(recovery_tool$result$isError)
  expect_null(recovery_tool$error)

  process$write_input(paste0(messages$rich_tool_call, "\n"))
  rich_tool <- read_stdio_response(process)
  expect_equal(rich_tool$id, 7)
  expect_identical(
    vapply(rich_tool$result$content, `[[`, character(1), "type"),
    c("text", "image", "resource")
  )
  expect_identical(rich_tool$result$content[[1]]$text, "first")
  expect_identical(rich_tool$result$content[[2]]$mimeType, "image/png")
  expect_identical(
    rich_tool$result$content[[3]]$resource$mimeType,
    "text/plain"
  )
  expect_identical(
    rich_tool$result$structuredContent,
    list(ok = TRUE, values = list(1L, 2L))
  )
  expect_identical(rich_tool$result$`_meta`, list(trace_id = "stdio"))
  expect_false(rich_tool$result$isError)
  expect_null(rich_tool$error)

  expect_true(process$is_alive())
  expect_length(process$read_error_lines(), 0)
})

test_that("stdio contains unsupported rich results and recovers", {
  skip_if_not_installed("processx")
  skip_if(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  process <- start_stdio_process("source")
  withr::defer(process$kill())
  messages <- stdio_client_messages()

  process$write_input(paste0(messages$initialize_old, "\n"))
  initialize_response <- read_stdio_response(process)
  expect_identical(initialize_response$result$protocolVersion, "2024-11-05")

  process$write_input(paste0(messages$initialized, "\n"))
  process$write_input(paste0(messages$audio_tool_call, "\n"))
  audio_tool <- read_stdio_response(process)
  expect_equal(audio_tool$id, 8)
  expect_true(audio_tool$result$isError)
  expect_identical(audio_tool$result$content[[1]]$type, "text")
  expect_match(audio_tool$result$content[[1]]$text, "audio")
  expect_null(audio_tool$error)

  process$write_input(paste0(messages$recovery_tool_call, "\n"))
  recovery_tool <- read_stdio_response(process)
  expect_equal(recovery_tool$id, 6)
  expect_false(recovery_tool$result$isError)
  expect_identical(recovery_tool$result$content[[1]]$text, "quiet")
  expect_null(recovery_tool$error)

  expect_true(process$is_alive())
  expect_length(process$read_error_lines(), 0)
})

test_that("stdio server exits when standard input closes", {
  skip_if_not_installed("processx")
  skip_if(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  process <- start_stdio_process("source")
  withr::defer(process$kill())

  close(process$get_input_connection())

  deadline <- Sys.time() + 3
  while (process$is_alive() && Sys.time() < deadline) {
    processx::poll(list(process), 100)
  }

  expect_false(process$is_alive())
  expect_identical(process$get_exit_status(), 0L)
  expect_length(process$read_error_lines(), 0)
})

test_that("stdio check-stage proof uses the installed mcplite package", {
  skip_if_not_installed("processx")
  skip_if_not(testthat::is_checking())
  withr::local_envvar(R_TESTS = "")

  expect_stdio_roundtrip(run_stdio_roundtrip("installed"))
})
