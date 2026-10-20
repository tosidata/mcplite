initialize_tool_state <- function(tool, protocol_version = "2025-11-25") {
  mcplite:::dispatch_message(
    initialize_request(protocol_version = protocol_version),
    mcplite:::new_server_state(tool)
  )$state
}

call_tool <- function(tool, protocol_version = "2025-11-25") {
  state <- initialize_tool_state(tool, protocol_version)
  mcplite:::dispatch_message(
    tool_call_request(name = "result_tool"),
    state
  )$response
}

call_modern_tool <- function(tool, state = NULL) {
  state <- state %||% mcplite:::new_server_state(tool)
  mcplite:::dispatch_message(
    modern_tool_call_request(name = "result_tool"),
    state
  )$response
}

test_that("content constructors create validated protocol-native blocks", {
  annotations <- list(
    audience = c("user", "assistant"),
    priority = 0.5,
    last_modified = "2026-07-18T12:00:00Z",
    extension_hint = "keep"
  )
  meta <- list(trace_id = "abc")

  blocks <- list(
    mcplite::content_text("hello", annotations = annotations, meta = meta),
    mcplite::content_image(
      data = "aW1hZ2U=",
      mime_type = "image/png",
      annotations = annotations,
      meta = meta
    ),
    mcplite::content_audio(
      data = "YXVkaW8=",
      mime_type = "audio/wav",
      annotations = annotations,
      meta = meta
    ),
    mcplite::content_resource_link(
      uri = "https://example.com/report.csv",
      name = "report.csv",
      title = "Report",
      description = "Generated report.",
      mime_type = "text/csv",
      size = 42L,
      annotations = annotations,
      meta = meta
    ),
    mcplite::content_resource(
      uri = "data:text/plain,hello",
      text = "hello",
      mime_type = "text/plain",
      annotations = annotations,
      meta = meta
    ),
    mcplite::content_resource(
      uri = "urn:example:binary",
      blob = "YmluYXJ5",
      mime_type = "application/octet-stream"
    )
  )

  expect_true(all(vapply(blocks, inherits, logical(1), "mcplite_content")))
  expect_identical(
    vapply(blocks, `[[`, character(1), "type"),
    c(
      "text",
      "image",
      "audio",
      "resource_link",
      "resource",
      "resource"
    )
  )

  expect_error(mcplite::content_text(c("a", "b")), "single string")
  expect_error(mcplite::content_image("data", c("a", "b")), "mime_type")
  expect_error(mcplite::content_audio(list("data"), "audio/wav"), "data")
  expect_error(mcplite::content_resource_link("", "name"), "uri")
  expect_error(
    mcplite::content_resource_link("urn:test", "name", size = -1L),
    "size"
  )
  expect_error(
    mcplite::content_resource("urn:test"),
    "exactly one"
  )
  expect_error(
    mcplite::content_resource("urn:test", text = "a", blob = "YQ=="),
    "exactly one"
  )
  expect_error(
    mcplite::content_text("x", annotations = list(audience = "system")),
    "audience"
  )
  expect_error(
    mcplite::content_text("x", annotations = list(priority = 2)),
    "priority"
  )
  expect_error(mcplite::content_text("x", meta = list(new.env())), "meta")
})

test_that("annotation standard fields do not consume prefix extensions", {
  extensions <- list(
    audience_extension = "system",
    priority_extension = 2,
    last_modified_extension = list(source = "custom")
  )

  for (extension_name in names(extensions)) {
    annotation <- extensions[extension_name]
    block <- mcplite::content_text("extension", annotations = annotation)
    result <- mcplite::tool_result(block)

    expect_identical(
      block$annotations,
      annotation,
      info = extension_name
    )
    expect_identical(
      result$content[[1]]$annotations,
      annotation,
      info = extension_name
    )
  }

  standard <- mcplite::content_text(
    "standard",
    annotations = list(
      audience = c("user", "assistant"),
      priority = 0.5,
      last_modified = "2026-07-18T12:00:00Z"
    )
  )
  expect_identical(
    standard$annotations,
    list(
      audience = list("user", "assistant"),
      priority = 0.5,
      last_modified = "2026-07-18T12:00:00Z"
    )
  )

  extension_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(
        mcplite::content_text("extension", annotations = extensions)
      )
    },
    name = "result_tool",
    description = "Return annotation extension fields."
  )
  extension_wire <- call_modern_tool(
    extension_tool
  )$result$content[[1]]$annotations

  expect_identical(extension_wire, extensions)
  expect_false(any(
    c("audience", "priority", "last_modified", "lastModified") %in%
      names(extension_wire)
  ))

  standard_tool <- mcplite::tool(
    function() mcplite::tool_result(standard),
    name = "result_tool",
    description = "Return standard annotation fields."
  )
  standard_wire <- call_modern_tool(
    standard_tool
  )$result$content[[1]]$annotations

  expect_identical(standard_wire[["audience"]], list("user", "assistant"))
  expect_identical(standard_wire[["priority"]], 0.5)
  expect_identical(
    standard_wire[["lastModified"]],
    "2026-07-18T12:00:00Z"
  )
  expect_false("last_modified" %in% names(standard_wire))
})

test_that("tool_result is the explicit result boundary", {
  text <- mcplite::content_text("hello")
  single <- mcplite::tool_result(text)
  multiple <- mcplite::tool_result(list(
    text,
    mcplite::content_image("aW1hZ2U=", "image/png")
  ))

  expect_s3_class(single, "mcplite_tool_result")
  expect_identical(single$content, list(text))
  expect_identical(
    vapply(multiple$content, `[[`, character(1), "type"),
    c(
      "text",
      "image"
    )
  )
  expect_error(
    mcplite::tool_result(list(type = "text", text = "raw")),
    "content_"
  )
  expect_error(
    mcplite::tool_result(list(list(type = "text", text = "raw"))),
    "content_"
  )
  forged <- structure(
    list(type = "text", annotations = named_list(), meta = named_list()),
    class = c("mcplite_content_text", "mcplite_content")
  )
  expect_error(mcplite::tool_result(forged), "content_")
  expect_error(mcplite::tool_result(), "content")
  expect_error(mcplite::tool_result(content = list()), "content")
  expect_error(mcplite::tool_result(is_error = NA), "is_error")
  expect_error(mcplite::tool_result(text, meta = list(new.env())), "meta")
})

test_that("invalid inherited results are contained at normalization", {
  forged_raw_content <- structure(
    list(
      content = list(list(type = "text", text = "raw MCP block")),
      structured_content = NULL,
      is_error = FALSE,
      meta = named_list()
    ),
    class = "mcplite_tool_result"
  )
  forged_is_error <- structure(
    list(
      content = list(mcplite::content_text("bad flag")),
      structured_content = NULL,
      is_error = "no",
      meta = named_list()
    ),
    class = "mcplite_tool_result"
  )
  forged_empty_content <- structure(
    list(
      content = list(),
      structured_content = NULL,
      is_error = FALSE,
      meta = named_list()
    ),
    class = "mcplite_tool_result"
  )
  mutated_block <- mcplite::tool_result(mcplite::content_text("before"))
  mutated_block$content[[1]]$text <- c("not", "scalar")

  invalid_results <- list(
    forged_raw_content = forged_raw_content,
    forged_is_error = forged_is_error,
    forged_empty_content = forged_empty_content,
    mutated_block = mutated_block
  )
  invalid_tools <- Map(
    function(result, name) {
      mcplite::tool(
        function() result,
        name = name,
        description = "Return an invalid inherited native result."
      )
    },
    invalid_results,
    names(invalid_results)
  )
  good_tool <- mcplite::tool(
    function() "recovered",
    name = "good_result",
    description = "Return after an invalid inherited result."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(c(invalid_tools, list(good_tool)))
  )$state

  for (name in names(invalid_results)) {
    bad <- mcplite:::dispatch_message(tool_call_request(name = name), state)
    state <- bad$state

    expect_null(bad$response$error, info = name)
    expect_true(bad$response$result$isError, info = name)
    expect_equal(length(bad$response$result$content), 1, info = name)
    expect_identical(
      bad$response$result$content[[1]]$type,
      "text",
      info = name
    )
    expect_true(
      is.character(bad$response$result$content[[1]]$text) &&
        length(bad$response$result$content[[1]]$text) == 1,
      info = name
    )

    good <- mcplite:::dispatch_message(
      tool_call_request(name = "good_result"),
      state
    )
    state <- good$state
    expect_null(good$response$error, info = name)
    expect_false(good$response$result$isError, info = name)
    expect_identical(
      good$response$result$content[[1]]$text,
      "recovered",
      info = name
    )
  }
})

test_that("structured content accepts every JSON shape with exact fallback", {
  values <- list(
    object = list(ok = TRUE, nested = list(values = list(1L, 2L))),
    array = list(1L, list(label = "two")),
    string = "value",
    number = 2.5,
    boolean = TRUE,
    empty_object = named_list(),
    empty_array = I(list()),
    json_null = NA
  )

  for (value_name in names(values)) {
    value <- values[[value_name]]
    result <- mcplite::tool_result(structured_content = value)

    expect_identical(result$structured_content, value, info = value_name)
    expect_identical(length(result$content), 1L, info = value_name)
    expect_identical(result$content[[1]]$type, "text", info = value_name)
    expected_fallback <- as.character(mcplite:::to_json(value))
    expect_identical(
      result$content[[1]]$text,
      expected_fallback,
      info = value_name
    )
    expect_false(
      inherits(result$content[[1]]$text, "json"),
      info = value_name
    )
  }

  explicit <- mcplite::tool_result(
    content = mcplite::content_text("custom"),
    structured_content = list(ok = TRUE),
    is_error = TRUE
  )
  absent <- mcplite::tool_result(
    content = mcplite::content_text("no structured value"),
    structured_content = NULL
  )

  expect_identical(explicit$content[[1]]$text, "custom")
  expect_true(explicit$is_error)
  expect_null(absent$structured_content)
  expect_error(
    mcplite::tool_result(structured_content = list(bad = new.env())),
    "structured_content"
  )
})

test_that("structured objects retain jsonlite mappings across protocols", {
  structured <- list(
    day = as.Date("2026-07-28"),
    rows = data.frame(x = 1:2),
    values = I(1L),
    label = factor("ready"),
    timestamp = as.POSIXct("2026-07-28 12:34:56", tz = "UTC"),
    empty_object = named_list(),
    empty_array = list(),
    empty_vector = integer(),
    empty_rows = data.frame(x = integer()),
    missing = list(
      logical = NA,
      character = NA_character_,
      integer = NA_integer_,
      double = NA_real_
    )
  )
  expected_json <- paste0(
    '{"day":"2026-07-28","rows":[{"x":1},{"x":2}],"values":[1],',
    '"label":"ready","timestamp":"2026-07-28 12:34:56",',
    '"empty_object":{},"empty_array":[],"empty_vector":[],"empty_rows":[],',
    '"missing":{"logical":null,"character":null,"integer":"NA","double":"NA"}}'
  )
  expected <- jsonlite::parse_json(expected_json, simplifyVector = FALSE)
  protocol_versions <- c(
    "2026-07-28",
    "2025-11-25",
    "2025-06-18",
    "2024-11-05"
  )

  for (explicit_content in c(FALSE, TRUE)) {
    result_tool <- mcplite::tool(
      function() {
        if (explicit_content) {
          mcplite::tool_result(
            content = mcplite::content_text("custom"),
            structured_content = structured
          )
        } else {
          mcplite::tool_result(structured_content = structured)
        }
      },
      name = "result_tool",
      description = "Return a named object with existing JSON mappings."
    )

    for (protocol_version in protocol_versions) {
      info <- paste(protocol_version, "explicit content:", explicit_content)
      response <- if (identical(protocol_version, "2026-07-28")) {
        call_modern_tool(result_tool)
      } else {
        call_tool(result_tool, protocol_version)
      }
      wire <- jsonlite::parse_json(
        mcplite:::to_json_response(response),
        simplifyVector = FALSE
      )

      expect_null(wire$error, info = info)
      expect_false(wire$result$isError, info = info)
      expect_identical(length(wire$result$content), 1L, info = info)
      expect_identical(wire$result$content[[1]]$type, "text", info = info)
      expect_identical(
        wire$result$content[[1]]$text,
        if (explicit_content) "custom" else expected_json,
        info = info
      )
      if (identical(protocol_version, "2024-11-05")) {
        expect_false("structuredContent" %in% names(wire$result), info = info)
      } else {
        expect_true("structuredContent" %in% names(wire$result), info = info)
        expect_identical(wire$result$structuredContent, expected, info = info)
      }
    }
  }
})

test_that("structured values follow serializer mappings across placements", {
  values <- list(
    date = as.Date("2026-07-28"),
    factor = factor("ready"),
    as_is = I(1L),
    rows = data.frame(x = 1:2),
    object = I(named_list(a = 1L)),
    missing = I(NA_integer_),
    nan = NaN,
    infinity = Inf
  )
  values$array <- unname(values)
  expected_json <- c(
    date = '"2026-07-28"',
    factor = '"ready"',
    as_is = "[1]",
    rows = '[{"x":1},{"x":2}]',
    object = '{"a":1}',
    missing = '["NA"]',
    nan = '"NaN"',
    infinity = '"Inf"',
    array = paste0(
      '["2026-07-28","ready",[1],[{"x":1},{"x":2}],',
      '{"a":1},["NA"],"NaN","Inf"]'
    )
  )

  for (value_name in names(values)) {
    value <- values[[value_name]]
    expected <- jsonlite::parse_json(
      expected_json[[value_name]],
      simplifyVector = FALSE
    )
    result_tool <- mcplite::tool(
      function() mcplite::tool_result(structured_content = value),
      name = "result_tool",
      description = "Return a value using its JSON mapping."
    )
    modern <- jsonlite::parse_json(
      mcplite:::to_json_response(call_modern_tool(result_tool)),
      simplifyVector = FALSE
    )

    expect_null(modern$error, info = value_name)
    expect_false(modern$result$isError, info = value_name)
    expect_identical(
      modern$result$structuredContent,
      expected,
      info = value_name
    )
    expect_identical(
      modern$result$content[[1]]$text,
      expected_json[[value_name]],
      info = value_name
    )

    if (value_name %in% c("rows", "object")) {
      for (protocol_version in c("2024-11-05", "2025-06-18", "2025-11-25")) {
        info <- paste(value_name, protocol_version)
        legacy <- jsonlite::parse_json(
          mcplite:::to_json_response(call_tool(result_tool, protocol_version)),
          simplifyVector = FALSE
        )

        expect_null(legacy$error, info = info)
        expect_false(legacy$result$isError, info = info)
        expect_identical(
          legacy$result$content[[1]]$text,
          expected_json[[value_name]],
          info = info
        )
        if (
          identical(value_name, "object") &&
            !identical(protocol_version, "2024-11-05")
        ) {
          expect_identical(
            legacy$result$structuredContent,
            expected,
            info = info
          )
        } else {
          expect_false(
            "structuredContent" %in% names(legacy$result),
            info = info
          )
        }
      }
    }
  }
})

test_that("root scalar NA follows class-specific defaults without coercion", {
  withr::local_options(list(
    mcplite.json.null = NULL, mcplite.json.na = NULL,
    mcplite.json.auto_unbox = NULL
  ))
  expected_json <- c(
    logical = "null", integer = '"NA"', double = '"NA"',
    character = "null", complex = '"NA"'
  )
  values <- list(
    logical = NA,
    integer = NA_integer_,
    double = NA_real_,
    character = NA_character_,
    complex = NA_complex_
  )
  protocol_versions <- c(
    "2026-07-28",
    "2025-11-25",
    "2025-06-18",
    "2024-11-05"
  )

  for (value_name in names(values)) {
    value <- values[[value_name]]
    result <- mcplite::tool_result(structured_content = value)
    expect_identical(result$structured_content, value, info = value_name)
    expect_identical(result$content[[1]]$text, expected_json[[value_name]],
      info = value_name
    )

    result_tool <- mcplite::tool(
      function() mcplite::tool_result(structured_content = value),
      name = "result_tool",
      description = "Return a root scalar NA using its JSON mapping."
    )
    for (protocol_version in protocol_versions) {
      info <- paste(value_name, protocol_version)
      response <- if (identical(protocol_version, "2026-07-28")) {
        call_modern_tool(result_tool)
      } else {
        call_tool(result_tool, protocol_version)
      }
      wire <- jsonlite::parse_json(
        mcplite:::to_json_response(response),
        simplifyVector = FALSE
      )

      expect_null(wire$error, info = info)
      expect_false(wire$result$isError, info = info)
      expect_identical(wire$result$content[[1]]$text, expected_json[[value_name]],
        info = info
      )
      if (identical(protocol_version, "2026-07-28")) {
        expect_true("structuredContent" %in% names(wire$result), info = info)
        expect_identical(wire$result$structuredContent,
          jsonlite::parse_json(expected_json[[value_name]]),
          info = info
        )
      } else {
        expect_false("structuredContent" %in% names(wire$result), info = info)
      }
    }
  }
})

test_that("root NA matrices retain dimensions and array wire shape", {
  value <- matrix(NA, nrow = 1L, ncol = 1L)
  result <- mcplite::tool_result(structured_content = value)

  expect_identical(result$structured_content, value)
  expect_identical(result$content[[1]]$text, "[[null]]")

  result_tool <- mcplite::tool(
    function() mcplite::tool_result(structured_content = value),
    name = "result_tool",
    description = "Return a one-cell matrix containing logical NA."
  )
  wire <- jsonlite::parse_json(
    mcplite:::to_json_response(call_modern_tool(result_tool)),
    simplifyVector = FALSE
  )

  expect_null(wire$error)
  expect_false(wire$result$isError)
  expect_identical(wire$result$structuredContent, list(list(NULL)))
  expect_identical(wire$result$content[[1]]$text, "[[null]]")
})

test_that("unsupported nested S3 values remain contained tool errors", {
  result_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(
        structured_content = list(value = structure(1L, class = "unsupported"))
      )
    },
    name = "result_tool",
    description = "Return an object without a JSON mapping."
  )

  for (protocol_version in c(
    "2026-07-28",
    "2025-11-25",
    "2025-06-18",
    "2024-11-05"
  )) {
    response <- if (identical(protocol_version, "2026-07-28")) {
      call_modern_tool(result_tool)
    } else {
      call_tool(result_tool, protocol_version)
    }
    wire <- jsonlite::parse_json(
      mcplite:::to_json_response(response),
      simplifyVector = FALSE
    )

    expect_null(wire$error, info = protocol_version)
    expect_true(wire$result$isError, info = protocol_version)
    expect_false(
      "structuredContent" %in% names(wire$result),
      info = protocol_version
    )
    expect_identical(length(wire$result$content), 1L, info = protocol_version)
    expect_identical(
      wire$result$content[[1]]$type,
      "text",
      info = protocol_version
    )
    expect_match(
      wire$result$content[[1]]$text,
      "structured_content",
      info = protocol_version
    )
  }
})

test_that("legacy ordinary values retain text conversion behavior", {
  values <- list(
    text = "literal",
    vector = c("a", "b"),
    json = '{"already":"json"}',
    number = 3.5,
    bare_list = list(label = "x", values = list(1L, 2L)),
    data_frame = data.frame(x = 1:2),
    null = NULL
  )

  expected <- list(
    text = "literal",
    vector = "a\nb",
    json = '{"already":"json"}',
    number = "3.5",
    bare_list = '{"label":"x","values":[1,2]}',
    data_frame = '[{"x":1},{"x":2}]',
    null = "{}"
  )

  for (name in names(values)) {
    value <- values[[name]]
    result_tool <- mcplite::tool(
      function() value,
      name = "result_tool",
      description = "Return a legacy value."
    )
    response <- call_tool(result_tool)

    expect_false(response$result$isError, info = name)
    expect_length(response$result$content, 1)
    expect_identical(response$result$content[[1]]$type, "text", info = name)
    expect_identical(
      as.character(response$result$content[[1]]$text),
      expected[[name]],
      info = name
    )
    expect_null(response$result$structuredContent, info = name)
  }
})

test_that("rich results preserve ordered wire blocks and field names", {
  result_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(
        content = list(
          mcplite::content_text("first", meta = list(block_trace = "first")),
          mcplite::content_image("aW1hZ2U=", "image/png"),
          mcplite::content_resource(
            "urn:example:text",
            text = "resource body",
            mime_type = "text/plain"
          ),
          mcplite::content_audio("YXVkaW8=", "audio/wav"),
          mcplite::content_resource_link(
            "https://example.com/data.csv",
            "data.csv",
            mime_type = "text/csv"
          )
        ),
        structured_content = list(ok = TRUE),
        meta = list(trace_id = "result-trace")
      )
    },
    name = "result_tool",
    description = "Return mixed rich content."
  )

  response <- call_tool(result_tool, "2025-06-18")
  result <- response$result

  expect_null(response$error)
  expect_false(result$isError)
  expect_identical(
    vapply(result$content, `[[`, character(1), "type"),
    c(
      "text",
      "image",
      "resource",
      "audio",
      "resource_link"
    )
  )
  expect_identical(result$content[[1]]$`_meta`, list(block_trace = "first"))
  expect_identical(result$content[[2]]$mimeType, "image/png")
  expect_identical(result$content[[3]]$resource$mimeType, "text/plain")
  expect_identical(result$content[[4]]$mimeType, "audio/wav")
  expect_identical(result$content[[5]]$mimeType, "text/csv")
  expect_identical(result$structuredContent, list(ok = TRUE))
  expect_identical(result$`_meta`, list(trace_id = "result-trace"))

  latest <- call_tool(result_tool, "2025-11-25")$result
  expect_identical(
    vapply(latest$content, `[[`, character(1), "type"),
    c(
      "text",
      "image",
      "resource",
      "audio",
      "resource_link"
    )
  )
  expect_identical(latest$structuredContent, list(ok = TRUE))
})

test_that("protocol versions gate rich result fields without partial success", {
  annotations <- list(
    audience = c("user", "assistant"),
    priority = 0.7,
    last_modified = "2026-07-18T12:00:00Z"
  )
  compatible_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(
        content = list(
          mcplite::content_text(
            "text",
            annotations = annotations,
            meta = list(block_trace = "text")
          ),
          mcplite::content_image("aW1hZ2U=", "image/png"),
          mcplite::content_resource("urn:test", text = "body")
        ),
        structured_content = list(ok = TRUE),
        meta = list(result_trace = "all")
      )
    },
    name = "result_tool",
    description = "Return version-compatible rich content."
  )

  old <- call_tool(compatible_tool, "2024-11-05")$result
  expect_false(old$isError)
  expect_identical(
    vapply(old$content, `[[`, character(1), "type"),
    c(
      "text",
      "image",
      "resource"
    )
  )
  expect_null(old$structuredContent)
  expect_identical(old$`_meta`, list(result_trace = "all"))
  expect_null(old$content[[1]]$`_meta`)
  expect_identical(
    old$content[[1]]$annotations$audience,
    list("user", "assistant")
  )
  expect_null(old$content[[1]]$annotations$lastModified)

  current <- call_tool(compatible_tool, "2025-11-25")$result
  expect_identical(current$structuredContent, list(ok = TRUE))
  expect_identical(current$content[[1]]$`_meta`, list(block_trace = "text"))
  expect_identical(
    current$content[[1]]$annotations$lastModified,
    "2026-07-18T12:00:00Z"
  )

  unsupported_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(list(
        mcplite::content_text("must not survive alone"),
        mcplite::content_audio("YXVkaW8=", "audio/wav")
      ))
    },
    name = "result_tool",
    description = "Return content unsupported by the old protocol."
  )
  unsupported <- call_tool(unsupported_tool, "2024-11-05")

  expect_null(unsupported$error)
  expect_true(unsupported$result$isError)
  expect_length(unsupported$result$content, 1)
  expect_identical(unsupported$result$content[[1]]$type, "text")
  expect_match(unsupported$result$content[[1]]$text, "audio")
  expect_false(grepl(
    "must not survive alone",
    unsupported$result$content[[1]]$text,
    fixed = TRUE
  ))

  link_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(mcplite::content_resource_link(
        "https://example.com/x",
        "x"
      ))
    },
    name = "result_tool",
    description = "Return a resource link."
  )
  link_error <- call_tool(link_tool, "2024-11-05")
  expect_true(link_error$result$isError)
  expect_match(link_error$result$content[[1]]$text, "resource_link")
})

test_that("embedded resource metadata stays on the outer block", {
  result_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(mcplite::content_resource(
        "urn:example:metadata",
        text = "body",
        meta = list(trace_id = "outer-only")
      ))
    },
    name = "result_tool",
    description = "Return embedded resource metadata."
  )

  old <- call_tool(result_tool, "2024-11-05")$result$content[[1]]
  expect_null(old$`_meta`)
  expect_null(old$resource$`_meta`)

  current <- call_tool(result_tool, "2025-06-18")$result$content[[1]]
  expect_identical(current$`_meta`, list(trace_id = "outer-only"))
  expect_null(current$resource$`_meta`)

  latest <- call_tool(result_tool, "2025-11-25")$result$content[[1]]
  expect_identical(latest$`_meta`, list(trace_id = "outer-only"))
  expect_null(latest$resource$`_meta`)
})

test_that("structured-only results use fallback on old protocols", {
  result_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(
        structured_content = list(ok = TRUE, values = list(1L, 2L)),
        is_error = TRUE
      )
    },
    name = "result_tool",
    description = "Return structured content only."
  )

  old <- call_tool(result_tool, "2024-11-05")$result
  expect_true(old$isError)
  expect_null(old$structuredContent)
  expect_identical(
    jsonlite::parse_json(old$content[[1]]$text, simplifyVector = FALSE),
    list(ok = TRUE, values = list(1L, 2L))
  )

  current <- call_tool(result_tool, "2025-06-18")$result
  expect_true(current$isError)
  expect_identical(
    current$structuredContent,
    list(ok = TRUE, values = list(1L, 2L))
  )
  expect_length(current$content, 1)
})

test_that("object output schemas retain legacy version gating and wire shape", {
  object_schema <- mcplite::type_object(
    ok = mcplite::type_boolean(),
    values = mcplite::type_array(mcplite::type_integer())
  )
  schema_tool <- mcplite::tool(
    function() mcplite::tool_result(structured_content = list(ok = TRUE)),
    name = "result_tool",
    description = "Return structured output.",
    output_schema = object_schema
  )

  old_state <- initialize_tool_state(schema_tool, "2024-11-05")
  old <- mcplite:::dispatch_message(tools_list_request(), old_state)
  expect_null(old$response$result$tools[[1]]$outputSchema)

  current_state <- initialize_tool_state(schema_tool, "2025-06-18")
  current <- mcplite:::dispatch_message(tools_list_request(), current_state)
  expect_identical(
    current$response$result$tools[[1]]$outputSchema$type,
    "object"
  )
  expect_identical(
    current$response$result$tools[[1]]$outputSchema$properties$values$type,
    "array"
  )

  latest_state <- initialize_tool_state(schema_tool, "2025-11-25")
  latest <- mcplite:::dispatch_message(tools_list_request(), latest_state)
  expect_identical(
    latest$response$result$tools[[1]]$outputSchema$type,
    "object"
  )

  empty_object_tool <- mcplite::tool(
    function() "ok",
    name = "empty_object_tool",
    description = "Use the canonical empty object schema.",
    output_schema = mcplite::type_object()
  )
  empty_object_state <- initialize_tool_state(empty_object_tool)
  empty_object_schema <- mcplite:::dispatch_message(
    tools_list_request(),
    empty_object_state
  )$response$result$tools[[1]]$outputSchema
  expect_true(mcplite:::empty_named_list(empty_object_schema$properties))
  expect_match(
    mcplite:::to_json(empty_object_schema),
    '"properties":\\{\\}'
  )

  explicit_empty_object <- structure(list(), names = character())
  raw_schema_tool <- mcplite::tool(
    function() "ok",
    name = "raw_schema_tool",
    description = "Preserve a list-backed empty object.",
    output_schema = mcplite::type_from_schema(list(
      type = "object",
      properties = explicit_empty_object
    ))
  )
  raw_state <- initialize_tool_state(raw_schema_tool)
  raw <- mcplite:::dispatch_message(tools_list_request(), raw_state)
  raw_output_schema <- raw$response$result$tools[[1]]$outputSchema
  expect_true(mcplite:::empty_named_list(raw_output_schema$properties))
  expect_match(
    mcplite:::to_json(raw_output_schema),
    '"properties":\\{\\}'
  )

  raw_array_tool <- mcplite::tool(
    function() "ok",
    name = "raw_array_tool",
    description = "Preserve a list-backed empty array.",
    output_schema = mcplite::type_from_schema(list(
      type = "object",
      properties = list()
    ))
  )
  raw_array_state <- initialize_tool_state(raw_array_tool)
  raw_array_schema <- mcplite:::dispatch_message(
    tools_list_request(),
    raw_array_state
  )$response$result$tools[[1]]$outputSchema
  expect_null(names(raw_array_schema$properties))
  expect_match(
    mcplite:::to_json(raw_array_schema),
    '"properties":\\[\\]'
  )

  parsed_schema_tool <- mcplite::tool(
    function() "ok",
    name = "parsed_schema_tool",
    description = "Use a parsed object output schema.",
    output_schema = mcplite::type_from_schema(
      '{"type":"object","properties":{}}'
    )
  )
  parsed_state <- initialize_tool_state(parsed_schema_tool)
  parsed <- mcplite:::dispatch_message(tools_list_request(), parsed_state)
  expect_identical(
    parsed$response$result$tools[[1]]$outputSchema,
    list(type = "object", properties = named_list())
  )

  instance_data_tool <- mcplite::tool(
    function() "ok",
    name = "instance_data_tool",
    description = "Preserve arrays in schema instance data.",
    output_schema = mcplite::type_from_schema(list(
      type = "object",
      examples = list(list(properties = list("first", "second"))),
      const = list(definitions = list("alpha", "beta"))
    ))
  )
  instance_data_state <- initialize_tool_state(instance_data_tool)
  instance_data_schema <- mcplite:::dispatch_message(
    tools_list_request(),
    instance_data_state
  )$response$result$tools[[1]]$outputSchema
  expect_null(names(instance_data_schema$examples[[1]]$properties))
  expect_null(names(instance_data_schema$const$definitions))
  expect_match(
    mcplite:::to_json(instance_data_schema),
    '"properties":\\["first","second"\\]'
  )
  expect_match(
    mcplite:::to_json(instance_data_schema),
    '"definitions":\\["alpha","beta"\\]'
  )

  array_schema_tool <- mcplite::tool(
    function() "ok",
    name = "array_schema_tool",
    description = "Preserve list-backed schema arrays.",
    output_schema = mcplite::type_from_schema(list(
      type = "object",
      required = list("value"),
      allOf = list(
        list(properties = list(value = list(type = "string")))
      )
    ))
  )
  array_state <- initialize_tool_state(array_schema_tool)
  array_schema <- mcplite:::dispatch_message(
    tools_list_request(),
    array_state
  )$response$result$tools[[1]]$outputSchema
  expect_null(names(array_schema$required))
  expect_null(names(array_schema$allOf))
  expect_match(mcplite:::to_json(array_schema), '"required":\\["value"\\]')
  expect_match(mcplite:::to_json(array_schema), '"allOf":\\[')

  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer_schema_tool <- mcplite::tool(
      function() "ok",
      name = "ellmer_schema_tool",
      description = "Use a compatible ellmer output schema helper.",
      output_schema = ellmer::type_object(ok = ellmer::type_boolean())
    )
    ellmer_state <- initialize_tool_state(ellmer_schema_tool)
    ellmer_schema <- mcplite:::dispatch_message(
      tools_list_request(),
      ellmer_state
    )$response$result$tools[[1]]$outputSchema
    expect_identical(ellmer_schema$type, "object")

    empty_ellmer_tool <- mcplite::tool(
      function() "ok",
      name = "empty_ellmer_tool",
      description = "Use a compatible empty ellmer object schema.",
      output_schema = ellmer::type_object()
    )
    empty_ellmer_state <- initialize_tool_state(empty_ellmer_tool)
    empty_ellmer_schema <- mcplite:::dispatch_message(
      tools_list_request(),
      empty_ellmer_state
    )$response$result$tools[[1]]$outputSchema
    expect_true(mcplite:::empty_named_list(empty_ellmer_schema$properties))
  }

  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad_data_frame",
      description = "Reject an array-shaped data frame schema.",
      output_schema = mcplite::type_from_schema(data.frame(type = "object"))
    ),
    "object"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "nested_property_data_frame",
      description = "Reject a data frame nested under properties.",
      output_schema = mcplite::type_from_schema(list(
        type = "object",
        properties = list(value = data.frame(type = "string"))
      ))
    ),
    "classed list"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "nested_definition_data_frame",
      description = "Reject a data frame nested under definitions.",
      output_schema = mcplite::type_from_schema(list(
        type = "object",
        definitions = list(Value = data.frame(type = "string"))
      ))
    ),
    "classed list"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "nested_classed_list",
      description = "Reject another classed list schema container.",
      output_schema = mcplite::type_from_schema(list(
        type = "object",
        allOf = list(I(list(type = "object")))
      ))
    ),
    "classed list"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad_environment",
      description = "Reject an unserializable output schema.",
      output_schema = mcplite::type_from_schema(list(
        type = "object",
        bad = new.env()
      ))
    ),
    "serializable"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad_function",
      description = "Reject an unserializable output schema.",
      output_schema = mcplite::type_from_schema(list(
        type = "object",
        bad = function() NULL
      ))
    ),
    "serializable"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad",
      description = "Reject raw output schema lists.",
      output_schema = list(type = "object")
    ),
    "type helper"
  )
})

test_that("output schema shapes project by protocol version", {
  schemas <- list(
    object = mcplite::type_object(ok = mcplite::type_boolean()),
    array = mcplite::type_array(mcplite::type_string()),
    scalar = mcplite::type_number(),
    raw = mcplite::type_from_schema(list(
      `$defs` = list(Value = list(type = "integer")),
      oneOf = list(
        list(`$ref` = "#/$defs/Value"),
        list(type = "null")
      ),
      `if` = list(type = "integer"),
      then = list(minimum = 0L),
      `else` = list(const = NULL)
    )),
    type_prefixed = mcplite::type_from_schema(list(
      typeExtension = "object",
      properties = named_list()
    ))
  )
  expected <- lapply(schemas, mcplite:::schema_from_tool_type)

  for (schema_name in names(schemas)) {
    output_schema <- schemas[[schema_name]]
    expected_schema <- expected[[schema_name]]
    result_tool <- mcplite::tool(
      function() "ok",
      name = "result_tool",
      description = "Project an output schema.",
      output_schema = output_schema
    )

    modern <- mcplite:::dispatch_message(
      modern_tools_list_request(),
      mcplite:::new_server_state(result_tool)
    )$response$result$tools[[1]]
    expect_identical(
      modern$outputSchema,
      expected_schema,
      info = schema_name
    )

    for (protocol_version in mcplite:::legacy_supported_protocol_versions) {
      state <- initialize_tool_state(result_tool, protocol_version)
      legacy <- mcplite:::dispatch_message(
        tools_list_request(),
        state
      )$response$result$tools[[1]]
      legacy_supports_schema <-
        !identical(protocol_version, "2024-11-05") &&
        identical(expected_schema[["type"]], "object")

      if (legacy_supports_schema) {
        expect_identical(
          legacy$outputSchema,
          expected_schema,
          info = paste(schema_name, protocol_version)
        )
      } else {
        expect_null(
          legacy$outputSchema,
          info = paste(schema_name, protocol_version)
        )
      }
    }
  }
})

test_that("structured JSON values project across every retained protocol", {
  values <- list(
    object = list(ok = TRUE),
    array = list(1L, 2L),
    one_element_array = list(1L),
    nested_null = list(value = NA),
    string = "value",
    number = 2.5,
    boolean = TRUE,
    empty_object = named_list(),
    empty_array = I(list()),
    json_null = NA
  )

  for (value_name in names(values)) {
    value <- values[[value_name]]
    expected_fallback <- as.character(mcplite:::to_json(value))
    result_tool <- local({
      structured_value <- value
      mcplite::tool(
        function() {
          mcplite::tool_result(structured_content = structured_value)
        },
        name = "result_tool",
        description = "Return one JSON structured value."
      )
    })

    modern <- call_modern_tool(result_tool)
    expect_true(
      "structuredContent" %in% names(modern$result),
      info = value_name
    )
    expect_identical(
      modern$result$structuredContent,
      value,
      info = value_name
    )
    expect_identical(modern$result$resultType, "complete", info = value_name)
    expect_null(modern$result$ttlMs, info = value_name)
    expect_null(modern$result$cacheScope, info = value_name)
    expect_identical(
      modern$result$content[[1]]$text,
      expected_fallback,
      info = value_name
    )

    modern_wire <- jsonlite::parse_json(
      mcplite:::to_json_response(modern),
      simplifyVector = FALSE
    )
    expect_true(
      "structuredContent" %in% names(modern_wire$result),
      info = value_name
    )
    expect_identical(
      modern_wire[["result"]][["content"]][[1]][["text"]],
      expected_fallback,
      info = value_name
    )
    if (identical(value_name, "one_element_array")) {
      expect_identical(modern_wire$result$structuredContent, list(1L))
    }
    if (identical(value_name, "nested_null")) {
      expect_true("value" %in% names(modern_wire$result$structuredContent))
      expect_null(modern_wire$result$structuredContent$value)
    }
    if (identical(value_name, "empty_object")) {
      expect_true(
        mcplite:::empty_named_list(modern_wire$result$structuredContent)
      )
    }
    if (identical(value_name, "empty_array")) {
      expect_identical(modern_wire$result$structuredContent, list())
    }
    if (identical(value_name, "json_null")) {
      expect_null(modern_wire$result$structuredContent)
    }

    is_object_value <- is.list(value) && !is.null(names(value))
    for (protocol_version in mcplite:::legacy_supported_protocol_versions) {
      legacy <- call_tool(result_tool, protocol_version)
      legacy_supports_value <-
        !identical(protocol_version, "2024-11-05") && is_object_value

      expect_identical(
        legacy$result$content[[1]]$text,
        expected_fallback,
        info = paste(value_name, protocol_version)
      )
      expect_null(
        legacy$result$resultType,
        info = paste(value_name, protocol_version)
      )
      if (legacy_supports_value) {
        expect_true(
          "structuredContent" %in% names(legacy$result),
          info = paste(value_name, protocol_version)
        )
        expect_identical(
          legacy$result$structuredContent,
          value,
          info = paste(value_name, protocol_version)
        )
      } else {
        info <- paste(value_name, protocol_version)
        expect_false(
          "structuredContent" %in% names(legacy$result),
          info = info
        )
        legacy_wire <- jsonlite::parse_json(
          mcplite:::to_json_response(legacy),
          simplifyVector = FALSE
        )
        expect_false(
          "structuredContent" %in% names(legacy_wire[["result"]]),
          info = info
        )
        expect_identical(
          legacy_wire[["result"]][["content"]][[1]][["text"]],
          expected_fallback,
          info = info
        )
      }
    }
  }
})

test_that("real modern tool results are decorated once after normalization", {
  canonical_state <- new_test_state()
  canonical_info <- canonical_state$config$server_info
  reserved_key <- "io.modelcontextprotocol/serverInfo"
  authored_error <- mcplite::tool(
    function() {
      mcplite::tool_result(
        content = mcplite::content_text("domain error"),
        structured_content = list(ok = FALSE),
        is_error = TRUE,
        meta = named_list(
          "io.modelcontextprotocol/serverInfo" = list(
            name = "spoofed",
            version = "spoofed"
          ),
          "com.example/result" = list(kept = TRUE)
        )
      )
    },
    name = "authored_error",
    description = "Return an authored tool error."
  )
  fallback_tool <- mcplite::tool(
    function() {
      structure(
        list(
          content = list(mcplite::content_text("invalid")),
          structured_content = list(bad = new.env()),
          is_error = FALSE,
          meta = named_list()
        ),
        class = "mcplite_tool_result"
      )
    },
    name = "fallback",
    description = "Trigger result normalization fallback."
  )
  state <- mcplite:::new_server_state(list(authored_error, fallback_tool))

  authored <- mcplite:::dispatch_message(
    modern_tool_call_request(name = "authored_error"),
    state
  )
  fallback <- mcplite:::dispatch_message(
    modern_tool_call_request(name = "fallback"),
    authored$state
  )

  for (response in list(authored$response, fallback$response)) {
    expect_identical(response$result$resultType, "complete")
    expect_true(response$result$isError)
    expect_identical(response$result$`_meta`[[reserved_key]], canonical_info)
    expect_null(response$result$ttlMs)
    expect_null(response$result$cacheScope)
  }
  expect_true(
    authored$response$result$`_meta`[["com.example/result"]]$kept
  )
  expect_match(
    fallback$response$result$content[[1]]$text,
    "structured_content"
  )
})

test_that("rich result failures stay contained and later calls succeed", {
  bad_tool <- mcplite::tool(
    function() {
      mcplite::tool_result(structured_content = list(bad = new.env()))
    },
    name = "bad_result",
    description = "Return unserializable structured content."
  )
  good_tool <- mcplite::tool(
    function() "recovered",
    name = "good_result",
    description = "Return after a failed result."
  )
  state <- mcplite:::dispatch_message(
    initialize_request(),
    mcplite:::new_server_state(list(bad_tool, good_tool))
  )$state

  bad <- mcplite:::dispatch_message(
    tool_call_request(name = "bad_result"),
    state
  )
  good <- mcplite:::dispatch_message(
    tool_call_request(name = "good_result"),
    bad$state
  )

  expect_null(bad$response$error)
  expect_true(bad$response$result$isError)
  expect_match(bad$response$result$content[[1]]$text, "structured_content")
  expect_null(good$response$error)
  expect_false(good$response$result$isError)
  expect_identical(good$response$result$content[[1]]$text, "recovered")
})

test_that("ellmer content adaptation is conservative", {
  skip_if_not_installed("ellmer")

  text_tool <- ellmer::tool(
    function() ellmer::ContentText("ellmer text"),
    name = "result_tool",
    description = "Return public ellmer text content."
  )
  text <- call_tool(text_tool)$result
  expect_false(text$isError)
  expect_identical(text$content[[1]]$type, "text")
  expect_identical(text$content[[1]]$text, "ellmer text")

  image_tool <- ellmer::tool(
    function() {
      ellmer::ContentImageInline(type = "image/png", data = "aW1hZ2U=")
    },
    name = "result_tool",
    description = "Return public ellmer inline image content."
  )
  image <- call_tool(image_tool)$result
  expect_false(image$isError)
  expect_identical(image$content[[1]]$type, "image")
  expect_identical(image$content[[1]]$mimeType, "image/png")
  expect_identical(image$content[[1]]$data, "aW1hZ2U=")

  list_tool <- ellmer::tool(
    function() {
      list(
        ellmer::ContentText("first"),
        ellmer::ContentImageInline(type = "image/png", data = "aW1hZ2U=")
      )
    },
    name = "result_tool",
    description = "Return ordered public ellmer content."
  )
  content <- call_tool(list_tool)$result$content
  expect_identical(
    vapply(content, `[[`, character(1), "type"),
    c("text", "image")
  )

  remote_tool <- ellmer::tool(
    function() ellmer::ContentImageRemote("https://example.com/image.png"),
    name = "result_tool",
    description = "Return unsupported remote content."
  )
  remote <- call_tool(remote_tool)$result
  expect_true(remote$isError)
  expect_match(remote$content[[1]]$text, "explicit")
  expect_match(remote$content[[1]]$text, "content_image")

  pdf_tool <- ellmer::tool(
    function() {
      ellmer::ContentPDF(
        type = "application/pdf",
        data = "cGRm",
        filename = "report.pdf"
      )
    },
    name = "result_tool",
    description = "Return unsupported PDF content."
  )
  pdf <- call_tool(pdf_tool)$result
  expect_true(pdf$isError)
  expect_match(pdf$content[[1]]$text, "content_resource")

  mixed_tool <- ellmer::tool(
    function() list(ellmer::ContentText("text"), "ordinary"),
    name = "result_tool",
    description = "Return mixed ellmer and ordinary content."
  )
  mixed <- call_tool(mixed_tool)$result
  expect_true(mixed$isError)
  expect_match(mixed$content[[1]]$text, "entirely")
})

test_that("payload defaults preserve published ordinary and nested mappings", {
  withr::local_options(list(
    mcplite.json.null = NULL,
    mcplite.json.na = NULL,
    mcplite.json.auto_unbox = NULL
  ))
  value <- list(
    missing = list(
      logical = NA, character = NA_character_,
      integer = NA_integer_, double = NA_real_, complex = NA_complex_
    ),
    nonfinite = c(NaN, Inf, -Inf),
    classed = list(
      date = as.Date(NA_character_),
      time = as.POSIXct(NA_character_, tz = "UTC"),
      factor = factor(NA_character_)
    ),
    rows = data.frame(
      id = 1L, logical = NA, integer = NA_integer_,
      double = NA_real_, character = NA_character_,
      date = as.Date(NA_character_),
      time = as.POSIXct(NA_character_, tz = "UTC"),
      factor = factor(NA_character_)
    ),
    null = NULL, object = named_list(), array = list(),
    vector = c(1, NA_real_), matrix = matrix(NA_integer_, 1),
    as_is = I(NA_integer_), unboxed = jsonlite::unbox(1L)
  )
  expected <- paste0(
    '{"missing":{"logical":null,"character":null,"integer":"NA",',
    '"double":"NA","complex":"NA"},"nonfinite":["NaN","Inf","-Inf"],',
    '"classed":{"date":null,"time":null,"factor":null},"rows":[{"id":1}],',
    '"null":null,"object":{},"array":[],"vector":[1,"NA"],',
    '"matrix":[["NA"]],"as_is":["NA"],"unboxed":1}'
  )

  for (structured in c(FALSE, TRUE)) {
    result_tool <- mcplite::tool(
      function() {
        if (structured) mcplite::tool_result(structured_content = value) else value
      },
      name = "result_tool", description = "Return published JSON mappings."
    )
    response <- call_modern_tool(result_tool)
    wire <- jsonlite::parse_json(mcplite:::to_json_response(response))
    expect_false(wire$result$isError)
    expect_identical(wire$result$content[[1]]$text, expected)
    if (structured) {
      expect_identical(response$result$structuredContent, value)
      expect_identical(wire$result$structuredContent, jsonlite::parse_json(expected))
    }
  }
})

test_that("bare empty structured roots restore the published object convention", {
  withr::local_options(list(
    mcplite.json.null = "list", mcplite.json.na = "null",
    mcplite.json.auto_unbox = FALSE
  ))
  canonical <- mcplite::tool_result(structured_content = list())
  expect_identical(canonical$structured_content, named_list())
  expect_identical(canonical$content[[1]]$text, "{}")
  expect_named(canonical, c("content", "structured_content", "is_error", "meta"))

  result_tool <- mcplite::tool(
    function() canonical,
    name = "result_tool",
    description = "Return an empty structured object."
  )
  for (version in c("2026-07-28", "2025-11-25", "2025-06-18", "2024-11-05")) {
    response <- if (version == "2026-07-28") {
      call_modern_tool(result_tool)
    } else {
      call_tool(result_tool, version)
    }
    wire_json <- as.character(mcplite:::to_json_response(response))
    wire <- jsonlite::parse_json(wire_json)
    expect_false(wire$result$isError, info = version)
    expect_identical(wire$result$content[[1]]$text, "{}", info = version)
    if (version == "2024-11-05") {
      expect_false("structuredContent" %in% names(wire$result))
    } else {
      expect_match(wire_json, '"structuredContent":{}', fixed = TRUE)
    }
  }
  expect_identical(mcplite:::tool_value_to_text(list()), structure("[]", class = "json"))
  nested <- mcplite::tool_result(structured_content = list(array = list()))
  expect_identical(nested$content[[1]]$text, '{"array":[]}')
})

test_that("each payload setting controls fallback and actual result encoding", {
  cases <- list(
    list(
      options = list(mcplite.json.na = "null"),
      value = NA_integer_,
      json = "null"
    ),
    list(
      options = list(mcplite.json.na = "string"),
      value = NA,
      json = '"NA"'
    ),
    list(
      options = list(mcplite.json.auto_unbox = FALSE),
      value = 1L,
      json = "[1]"
    ),
    list(
      options = list(mcplite.json.null = "list"),
      value = list(keep = NULL, one = 1L, nested = list()),
      json = '{"keep":{},"one":1,"nested":[]}'
    ),
    list(
      options = list(mcplite.json.na = "null"),
      value = list(
        numbers = c(1, NA_real_, NaN, Inf, -Inf),
        rows = data.frame(id = 1L, x = NA_real_)
      ),
      json = '{"numbers":[1,null,null,null,null],"rows":[{"id":1,"x":null}]}'
    ),
    list(
      options = list(mcplite.json.na = "string"),
      value = list(missing = NA, rows = data.frame(x = NA_real_)),
      json = '{"missing":"NA","rows":[{"x":"NA"}]}'
    ),
    list(
      options = list(mcplite.json.auto_unbox = FALSE),
      value = list(
        one = 1L, date = as.Date("2026-07-28"),
        time = as.POSIXct("2026-07-28 12:34:56", tz = "UTC"),
        factor = factor("ready"), as_is = I(1L),
        unboxed = jsonlite::unbox(1L), matrix = matrix(1L, 1)
      ),
      json = paste0(
        '{"one":[1],"date":["2026-07-28"],',
        '"time":["2026-07-28 12:34:56"],"factor":["ready"],',
        '"as_is":[1],"unboxed":1,"matrix":[[1]]}'
      )
    )
  )
  for (case in cases) {
    settings <- list(
      mcplite.json.null = NULL, mcplite.json.na = NULL,
      mcplite.json.auto_unbox = NULL
    )
    settings[names(case$options)] <- case$options
    withr::with_options(settings, {
      value <- case$value
      for (structured in c(FALSE, TRUE)) {
        result_tool <- mcplite::tool(
          function() {
            if (structured) mcplite::tool_result(structured_content = value) else value
          },
          name = "result_tool", description = "Return configurable JSON."
        )
        response <- call_modern_tool(result_tool)
        wire <- jsonlite::parse_json(mcplite:::to_json_response(response))
        expect_false(wire$result$isError)
        expect_identical(wire$result$content[[1]]$text, case$json)
        if (structured) {
          expect_identical(
            wire$result$structuredContent,
            jsonlite::parse_json(case$json)
          )
          expect_identical(response$result$structuredContent, value)
        }
      }
    })
  }
})

test_that("encoded structured shapes project without changing explicit content", {
  withr::local_options(list(mcplite.json.auto_unbox = FALSE))
  value <- jsonlite::toJSON(list(n = 1L), auto_unbox = TRUE)
  expected <- '["{\\"n\\":1}"]'
  for (explicit in c(FALSE, TRUE)) {
    result_tool <- mcplite::tool(
      function() {
        if (explicit) {
          mcplite::tool_result(mcplite::content_text(value), structured_content = value)
        } else {
          mcplite::tool_result(structured_content = value)
        }
      },
      name = "result_tool", description = "Return JSON as text, not raw JSON."
    )
    for (version in c("2026-07-28", "2025-11-25", "2025-06-18", "2024-11-05")) {
      response <- if (version == "2026-07-28") {
        call_modern_tool(result_tool)
      } else {
        call_tool(result_tool, version)
      }
      wire <- jsonlite::parse_json(mcplite:::to_json_response(response))
      expect_false(wire$result$isError)
      expect_identical(
        wire$result$content[[1]]$text,
        if (explicit) as.character(value) else expected
      )
      expect_identical(
        "structuredContent" %in% names(wire$result),
        version == "2026-07-28"
      )
      if (version == "2026-07-28") {
        expect_identical(wire$result$structuredContent, list(as.character(value)))
      }
    }
  }
})

test_that("ordinary NULL and character text bypass even broken payload settings", {
  withr::local_options(list(
    mcplite.json.null = "invalid", mcplite.json.na = "invalid",
    mcplite.json.auto_unbox = NA
  ))
  values <- list(NULL, c("one", "two"), structure('{"n":1}', class = "json"))
  expected <- c("{}", "one\ntwo", '{"n":1}')
  for (i in seq_along(values)) {
    result_tool <- mcplite::tool(
      function() values[[i]],
      name = "result_tool",
      description = "Return ordinary text or NULL."
    )
    response <- call_modern_tool(result_tool)
    wire <- jsonlite::parse_json(mcplite:::to_json_response(response))
    expect_false(wire$result$isError)
    expect_identical(wire$result$content[[1]]$text, expected[[i]])
    expect_false("structuredContent" %in% names(wire$result))
  }
  result_tool <- mcplite::tool(
    function() mcplite::tool_result(mcplite::content_text("absent")),
    name = "result_tool", description = "Omit structured content."
  )
  expect_false(call_modern_tool(result_tool)$result$isError)
})
