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
  forged_scalar_structured <- structure(
    list(
      content = list(mcplite::content_text("scalar structured content")),
      structured_content = 1,
      is_error = FALSE,
      meta = named_list()
    ),
    class = "mcplite_tool_result"
  )
  forged_array_structured <- structure(
    list(
      content = list(mcplite::content_text("array structured content")),
      structured_content = list(1, 2),
      is_error = FALSE,
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
  mutated_result <- mcplite::tool_result(mcplite::content_text("before"))
  mutated_result$structured_content <- 1
  mutated_block <- mcplite::tool_result(mcplite::content_text("before"))
  mutated_block$content[[1]]$text <- c("not", "scalar")

  invalid_results <- list(
    forged_raw_content = forged_raw_content,
    forged_is_error = forged_is_error,
    forged_scalar_structured = forged_scalar_structured,
    forged_array_structured = forged_array_structured,
    forged_empty_content = forged_empty_content,
    mutated_result = mutated_result,
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

test_that("structured content uses exact fallback rules and object shapes", {
  structured <- list(
    ok = TRUE,
    nested = list(items = list(1L, 2L), object = list(label = "x"))
  )
  fallback <- mcplite::tool_result(structured_content = structured)
  explicit <- mcplite::tool_result(
    content = mcplite::content_text("custom"),
    structured_content = structured,
    is_error = TRUE
  )
  empty <- mcplite::tool_result(structured_content = list())

  expect_length(fallback$content, 1)
  expect_identical(fallback$content[[1]]$type, "text")
  expect_identical(
    jsonlite::parse_json(fallback$content[[1]]$text, simplifyVector = FALSE),
    structured
  )
  expect_length(explicit$content, 1)
  expect_identical(explicit$content[[1]]$text, "custom")
  expect_true(explicit$is_error)
  expect_true(mcplite:::empty_named_list(empty$structured_content))
  expect_identical(as.character(empty$content[[1]]$text), "{}")

  expect_error(mcplite::tool_result(structured_content = 1), "object")
  expect_error(
    mcplite::tool_result(structured_content = list(1, 2)),
    "object"
  )
  expect_error(
    mcplite::tool_result(structured_content = list(bad = new.env())),
    "structured_content"
  )
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

test_that("native output schemas require object helpers and are version gated", {
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
      description = "Reject scalar output schema.",
      output_schema = mcplite::type_string()
    ),
    "object"
  )
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad",
      description = "Reject array output schema.",
      output_schema = mcplite::type_array(mcplite::type_string())
    ),
    "object"
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
  expect_error(
    mcplite::tool(
      function() "bad",
      name = "bad",
      description = "Reject raw scalar schema helpers.",
      output_schema = mcplite::type_from_schema(list(type = "string"))
    ),
    "object"
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
