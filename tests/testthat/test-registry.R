test_that("tool registry accepts direct mcplite tool inputs", {
  single_tool <- mcplite::tool(
    function() {
      "ok"
    },
    name = "single",
    description = "Return ok."
  )

  single_registry <- mcplite:::as_tool_registry(single_tool)
  expect_named(single_registry$tools, "single")

  list_registry <- mcplite:::as_tool_registry(list(single_tool))
  expect_named(list_registry$tools, "single")
})

test_that("tool registry optionally accepts ellmer tool inputs", {
  skip_if_not_installed("ellmer")

  single_tool <- ellmer::tool(
    function() {
      "ok"
    },
    name = "ellmer_single",
    description = "Return ok."
  )

  single_registry <- mcplite:::as_tool_registry(single_tool)
  expect_named(single_registry$tools, "ellmer_single")

  list_registry <- mcplite:::as_tool_registry(list(single_tool))
  expect_named(list_registry$tools, "ellmer_single")
})

test_that("tool registry rejects .R paths without sourcing them", {
  tool_file <- withr::local_tempfile(fileext = ".R")
  sourced_sentinel <- withr::local_tempfile()
  writeLines(
    c(
      sprintf("writeLines('sourced', %s)", deparse(sourced_sentinel)),
      "list(",
      "  mcplite::tool(",
      "    function() { 'from-file' },",
      "    name = 'from_file',",
      "    description = 'Loaded from a file.'",
      "  )",
      ")"
    ),
    tool_file
  )

  expect_error(
    mcplite:::as_tool_registry(tool_file),
    "mcplite::tool"
  )
  expect_false(file.exists(sourced_sentinel))
})

test_that("tool registry rejects duplicate tool names", {
  duplicated_tools <- list(
    mcplite::tool(
      function() {
        "one"
      },
      name = "duplicate",
      description = "First tool."
    ),
    mcplite::tool(
      function() {
        "two"
      },
      name = "duplicate",
      description = "Second tool."
    )
  )

  expect_error(
    mcplite:::as_tool_registry(duplicated_tools),
    "Tool names must be unique"
  )
})
