test_that("payload defaults retain class-specific jsonlite mappings", {
  withr::local_options(list(
    mcplite.json.null = NULL,
    mcplite.json.na = NULL,
    mcplite.json.auto_unbox = NULL
  ))
  value <- list(
    integer = NA_integer_,
    logical = NA,
    character = NA_character_,
    rows = data.frame(id = 1L, missing = NA_real_),
    empty = NULL,
    object = named_list(),
    array = list()
  )

  expect_identical(
    as.character(mcplite:::to_payload_json(value)),
    paste0(
      '{"integer":"NA","logical":null,"character":null,',
      '"rows":[{"id":1}],"empty":null,"object":{},"array":[]}'
    )
  )
  expect_identical(mcplite:::to_payload_json(value), mcplite:::to_json(value))
})

test_that("unset payload na omits the argument rather than forwarding NULL", {
  withr::local_options(list(
    mcplite.json.null = NULL,
    mcplite.json.na = NULL,
    mcplite.json.auto_unbox = NULL
  ))
  value <- list(missing = NA_integer_)

  expect_identical(
    as.character(mcplite:::to_payload_json(value)),
    '{"missing":"NA"}'
  )
  expect_identical(
    as.character(jsonlite::toJSON(value, auto_unbox = TRUE, na = NULL)),
    '{"missing":null}'
  )

  options(mcplite.json.na = "null")
  expect_identical(
    as.character(mcplite:::to_payload_json(value)),
    '{"missing":null}'
  )
  options(mcplite.json.na = "string")
  expect_identical(as.character(mcplite:::to_payload_json(NA)), '"NA"')
  options(mcplite.json.na = NULL)
  expect_identical(as.character(mcplite:::to_payload_json(NA_integer_)), '"NA"')
})

test_that("payload options change only their selected jsonlite mappings", {
  withr::local_options(list(
    mcplite.json.null = "list",
    mcplite.json.na = "null",
    mcplite.json.auto_unbox = FALSE,
    mcplite.json.digits = 1
  ))
  value <- list(count = 1L, missing = NA_integer_, empty = NULL, array = list())

  expect_identical(
    as.character(mcplite:::to_payload_json(value)),
    '{"count":[1],"missing":[null],"empty":{},"array":[]}'
  )
  expect_identical(as.character(mcplite:::to_payload_json(1.2345)), "[1.2345]")
  expect_identical(
    as.character(mcplite:::to_json(value)),
    '{"count":1,"missing":"NA","empty":null,"array":[]}'
  )

  options(mcplite.json.null = "null", mcplite.json.auto_unbox = TRUE)
  expect_identical(
    as.character(mcplite:::to_payload_json(value)),
    '{"count":1,"missing":null,"empty":null,"array":[]}'
  )
})

test_that("payload settings leave protocol fields unchanged", {
  withr::local_options(list(
    mcplite.json.null = "list",
    mcplite.json.na = "string",
    mcplite.json.auto_unbox = FALSE
  ))
  json_text <- structure('{"not":"raw"}', class = "json")
  result <- list(
    content = list(list(
      type = "text",
      text = json_text,
      annotations = list(audience = list("user"), priority = 1),
      `_meta` = list(flag = TRUE, empty = NULL)
    )),
    isError = FALSE,
    structuredContent = list(count = 1L, missing = NA, empty = NULL),
    `_meta` = list(flag = TRUE, empty = NULL),
    resultType = "complete"
  )
  expected_result <- paste0(
    '{"content":[{"type":"text","text":"{\\"not\\":\\"raw\\"}",',
    '"annotations":{"audience":["user"],"priority":1},',
    '"_meta":{"flag":true,"empty":null}}],"isError":false,',
    '"structuredContent":{"count":[1],"missing":["NA"],"empty":{}},',
    '"_meta":{"flag":true,"empty":null},"resultType":"complete"}'
  )

  expect_identical(
    as.character(mcplite:::tool_result_to_json(result)),
    expected_result
  )
  expect_identical(
    as.character(mcplite:::to_json_response(
      mcplite:::jsonrpc_response(NULL, result = result)
    )),
    paste0('{"jsonrpc":"2.0","id":null,"result":', expected_result, "}")
  )
  expect_identical(
    as.character(mcplite:::to_json_response(
      mcplite:::jsonrpc_response("request", result = result)
    )),
    paste0('{"jsonrpc":"2.0","id":"request","result":', expected_result, "}")
  )
})

test_that("payload roots retain jsonlite shapes without reinterpretation", {
  withr::local_options(list(
    mcplite.json.null = "list",
    mcplite.json.na = "null",
    mcplite.json.auto_unbox = FALSE
  ))
  cases <- list(
    list(value = 1L, json = "[1]"),
    list(value = NA_integer_, json = "[null]"),
    list(value = named_list(), json = "{}"),
    list(value = list(), json = "[]"),
    list(value = "text", json = '["text"]'),
    list(
      value = structure('{"not":"raw"}', class = "json"),
      json = '["{\\"not\\":\\"raw\\"}"]'
    )
  )

  for (case in cases) {
    response <- mcplite:::jsonrpc_response(7L, result = list(
      content = list(list(type = "text", text = "fallback")),
      isError = FALSE,
      structuredContent = case$value
    ))
    expect_identical(
      as.character(mcplite:::to_json_response(response)),
      paste0(
        '{"jsonrpc":"2.0","id":7,"result":{"content":[',
        '{"type":"text","text":"fallback"}],"isError":false,',
        '"structuredContent":', case$json, "}}"
      )
    )
  }
})

test_that("nonpayload responses do not consult invalid payload settings", {
  withr::local_options(list(
    mcplite.json.null = "invalid",
    mcplite.json.na = "invalid",
    mcplite.json.auto_unbox = FALSE
  ))
  expect_error(mcplite:::to_payload_json(1L), "arg")

  error_response <- mcplite:::jsonrpc_invalid_request()
  expect_identical(
    as.character(mcplite:::to_json_response(error_response)),
    paste0(
      '{"jsonrpc":"2.0","id":null,"error":',
      '{"code":-32600,"message":"Invalid Request"}}'
    )
  )
  tool_error <- list(
    content = list(list(type = "text", text = "failed")),
    isError = TRUE
  )
  expect_identical(
    mcplite:::tool_result_to_json(tool_error),
    mcplite:::to_json(tool_error)
  )
  tool_response <- mcplite:::jsonrpc_response(1L, result = tool_error)
  expect_identical(
    mcplite:::to_json_response(tool_response),
    mcplite:::to_json(tool_response)
  )
  listing <- mcplite:::jsonrpc_response(1L, result = list(tools = list(list(
    name = "example",
    inputSchema = list(type = "object", properties = named_list()),
    annotations = list(readOnlyHint = TRUE)
  ))))
  expect_identical(
    mcplite:::to_json_response(listing),
    mcplite:::to_json(listing)
  )
})

test_that("serializer-owned fragments preserve literal large integer digits", {
  # This fixture stands in for a fresh serializer output, not user raw JSON.
  testthat::local_mocked_bindings(
    to_payload_json = function(x) {
      structure('{"n":9007199254740993}', class = "json")
    },
    .package = "mcplite"
  )
  response <- mcplite:::jsonrpc_response(1L, result = list(
    content = list(list(type = "text", text = "large integer")),
    isError = FALSE,
    structuredContent = list(n = 1L)
  ))

  expect_identical(
    as.character(mcplite:::to_json_response(response)),
    paste0(
      '{"jsonrpc":"2.0","id":1,"result":{"content":[',
      '{"type":"text","text":"large integer"}],"isError":false,',
      '"structuredContent":{"n":9007199254740993}}}'
    )
  )
})
