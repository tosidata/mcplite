#' Define an MCP tool
#'
#' `tool()` wraps an R function with MCP metadata. The resulting object can be
#' supplied directly, or in a list, to [mcp_server()]. Ordinary function return
#' values use the default single-text-block conversion; return [tool_result()]
#' to opt into protocol-native content, structured output, or result metadata.
#'
#' @section Arguments and defaults:
#' Incoming JSON arrays reach `fun` as R lists, not atomic vectors. Schemas do
#' not coerce or validate argument values or supply R defaults. Marking a
#' property `required = FALSE` permits omission in the advertised schema; the
#' R function must provide its own default for calls that omit that argument.
#'
#' @section Return values:
#' Ordinary character values become literal text, not parsed JSON. Bare lists
#' are ordinary values, not MCP result objects. See
#' [Return-value mappings][mcplite-results] for exact conversions, empty and
#' missing values, and payload JSON options. Configure those options before
#' constructing results and starting the server.
#'
#' @section Complete schemas and structured output:
#' `arguments` also accepts one complete object-root schema from
#' [type_from_schema()]. Complete input schemas must have direct root
#' `type = "object"`; JSON Schema 2020-12 keywords such as `$schema`, `$defs`,
#' `$ref`, composition, and conditionals are preserved.
#'
#' An `output_schema` advertises the expected `structured_content` shape. A
#' client's protocol can omit an incompatible output schema without removing
#' the tool; see [mcp_server()] under "Protocol compatibility" for the exact
#' version rules. `mcplite` checks schema container shape and serializability,
#' not full schema validity or runtime input/output conformance. Tool authors
#' own those guarantees.
#'
#' @param fun Function to expose as a tool.
#' @param description A single string describing when and how to use the tool.
#' @param ... Not used. Supply argument schemas with `arguments`.
#' @param arguments Named list of argument schemas created by the `type_*()`
#'   helpers, or one complete direct object-root schema created by
#'   `type_from_schema()`.
#' @param name Optional tool name. If omitted, `tool()` uses the symbol name
#'   supplied to `fun`; anonymous functions must supply `name`. Tool names must
#'   use 1 to 128 characters from letters, digits, underscore, dot, and hyphen.
#' @param annotations Optional named list of MCP tool annotations to advertise.
#' @param output_schema Optional output schema created by a supported `type_*()`
#'   helper. Raw schema lists must be wrapped with [type_from_schema()]. See
#'   "Complete schemas and structured output" for author responsibilities and
#'   protocol compatibility.
#'
#' @return The supplied function with MCP metadata attached. It remains directly
#'   callable as an R function and can be supplied to [mcp_server()].
#' @export
#'
#' @examples
#' add_numbers <- tool(
#'   function(x, y) {
#'     x + y
#'   },
#'   name = "add_numbers",
#'   description = "Add two numbers and return the result.",
#'   arguments = list(
#'     x = type_number("First number."),
#'     y = type_number("Second number.")
#'   )
#' )
#' add_numbers(2, 3)
tool <- function(
  fun,
  description,
  ...,
  arguments = list(),
  name = NULL,
  annotations = list(),
  output_schema = NULL
) {
  if (!is.function(fun)) {
    stop("`fun` must be a function.", call. = FALSE)
  }

  check_scalar_string(description, "description")

  dots <- list(...)
  if (length(dots) > 0) {
    stop(
      "`...` is not supported; supply argument schemas with `arguments`.",
      call. = FALSE
    )
  }

  name <- tool_name(name, substitute(fun))

  input_schema <- normalize_tool_input_schema(arguments)

  if (!is_named_or_empty_list(annotations)) {
    stop("`annotations` must be a named list.", call. = FALSE)
  }

  output_schema <- normalize_tool_output_schema(output_schema)

  attr(fun, "mcplite_tool") <- list(
    name = name,
    description = description,
    input_schema = input_schema,
    annotations = annotations,
    output_schema = output_schema
  )
  class(fun) <- unique(c("mcplite_tool", class(fun), "function"))
  fun
}

#' Define MCP tool schemas
#'
#' These helpers create common JSON Schema descriptions for tool arguments and
#' output. `type_from_schema()` wraps a complete schema supplied as a list or
#' JSON string without removing JSON Schema 2020-12 keywords. A complete tool
#' input schema can be passed directly as `arguments = type_from_schema(...)`
#' when it has direct root `type = "object"`.
#'
#' When `$schema` is absent, MCP treats schemas as JSON Schema 2020-12. Authors
#' are responsible for schema validity and for runtime input/output conformance,
#' domain validation, authorization or access checks, side-effect safety,
#' output sanitization, and rate limiting where needed. List input preserves the
#' supplied R list shape: use a named empty list for `{}` and an unnamed empty
#' list for `[]`.
#'
#' Incoming JSON arrays remain R lists. These helpers do not coerce or validate
#' argument values or supply R defaults. If an argument may be omitted, give
#' the R function a default for it.
#'
#' `type_ignore()` omits an argument from the advertised schema. It does not
#' reject a caller-supplied argument or enforce permissions.
#'
#' @param description Optional argument description.
#' @param required Whether the argument is listed as required in the parent
#'   schema. `FALSE` permits omission but does not set an R default.
#'
#' @return A lightweight mcplite tool type object.
#' @examples
#' type_string("A label.")
#'
#' type_array(type_integer(), description = "Integer values.")
#'
#' type_object(
#'   .description = "A labeled score.",
#'   label = type_string(),
#'   score = type_number(required = FALSE)
#' )
#'
#' type_from_schema(list(
#'   type = "string",
#'   minLength = 1
#' ))
#' @name tool-types
NULL

#' @rdname tool-types
#' @export
type_boolean <- function(description = NULL, required = TRUE) {
  new_tool_type("boolean", description = description, required = required)
}

#' @rdname tool-types
#' @export
type_integer <- function(description = NULL, required = TRUE) {
  new_tool_type("integer", description = description, required = required)
}

#' @rdname tool-types
#' @export
type_number <- function(description = NULL, required = TRUE) {
  new_tool_type("number", description = description, required = required)
}

#' @rdname tool-types
#' @export
type_string <- function(description = NULL, required = TRUE) {
  new_tool_type("string", description = description, required = required)
}

#' @rdname tool-types
#' @param values Allowed enum values.
#' @export
type_enum <- function(values, description = NULL, required = TRUE) {
  if (length(values) == 0 || is.null(values)) {
    stop("`values` must contain at least one enum value.", call. = FALSE)
  }

  new_tool_type(
    "enum",
    description = description,
    required = required,
    values = as.list(values)
  )
}

#' @rdname tool-types
#' @param items Type helper describing each array item.
#' @export
type_array <- function(items, description = NULL, required = TRUE) {
  if (!is_supported_tool_type(items)) {
    stop(
      "`items` must be a mcplite or compatible ellmer type helper.",
      call. = FALSE
    )
  }

  new_tool_type(
    "array",
    description = description,
    required = required,
    items = items
  )
}

#' @rdname tool-types
#' @param ... Named properties for object schemas.
#' @param .description Optional object description.
#' @param .required Whether the object itself is listed as required in its
#'   parent schema.
#' @param .additional_properties Whether to allow additional properties.
#' @export
type_object <- function(
  .description = NULL,
  ...,
  .required = TRUE,
  .additional_properties = FALSE
) {
  properties <- list(...)

  if (!is_named_or_empty_list(properties)) {
    stop(
      "Object properties must be supplied as named type helpers.",
      call. = FALSE
    )
  }

  new_tool_type(
    "object",
    description = .description,
    required = .required,
    properties = normalize_tool_argument_types(properties),
    additional_properties = .additional_properties
  )
}

#' @rdname tool-types
#' @param text A JSON Schema as a list or JSON string.
#' @param path Path to a JSON Schema file. Exactly one of `text` or `path` must
#'   be supplied.
#' @importFrom jsonlite parse_json
#' @export
type_from_schema <- function(text = NULL, path = NULL) {
  if (is.null(text) == is.null(path)) {
    stop("Supply exactly one of `text` or `path`.", call. = FALSE)
  }

  schema <- if (!is.null(path)) {
    parse_json(
      paste(readLines(path, warn = FALSE), collapse = "\n"),
      simplifyVector = FALSE
    )
  } else if (is.character(text) && length(text) == 1) {
    parse_json(text, simplifyVector = FALSE)
  } else if (is.list(text)) {
    text
  } else {
    stop("`text` must be a schema list or a JSON string.", call. = FALSE)
  }

  new_tool_type("schema", required = TRUE, schema = schema)
}

#' @rdname tool-types
#' @export
type_ignore <- function() {
  new_tool_type("ignore", required = FALSE)
}

check_scalar_string <- function(x, arg) {
  if (!is_scalar_character(x)) {
    stop(sprintf("`%s` must be a single string.", arg), call. = FALSE)
  }
}

check_optional_scalar_string <- function(x, arg) {
  if (!is.null(x)) {
    check_scalar_string(x, arg)
  }
}

check_required_flag <- function(x) {
  if (!is.logical(x) || length(x) != 1 || is.na(x)) {
    stop("`required` must be TRUE or FALSE.", call. = FALSE)
  }
}

is_named_or_empty_list <- function(x) {
  is.list(x) &&
    (length(x) == 0 ||
      (!is.null(names(x)) && all(nzchar(names(x)))))
}

tool_name <- function(name, expression) {
  if (!is.null(name)) {
    check_tool_name(name)
    return(name)
  }

  if (is.symbol(expression)) {
    inferred_name <- as.character(expression)
    check_tool_name(inferred_name)
    return(inferred_name)
  }

  stop("`name` is required when `fun` is anonymous.", call. = FALSE)
}

check_tool_name <- function(name) {
  check_scalar_string(name, "name")

  if (!grepl("^[A-Za-z0-9_.-]{1,128}$", name)) {
    stop(
      "`name` must be 1 to 128 characters using only letters, digits, underscore, dot, or hyphen.",
      call. = FALSE
    )
  }
}

new_tool_type <- function(kind, description = NULL, required = TRUE, ...) {
  check_optional_scalar_string(description, "description")
  check_required_flag(required)

  structure(
    c(
      list(kind = kind, description = description, required = required),
      list(...)
    ),
    class = c(paste0("mcplite_tool_type_", kind), "mcplite_tool_type")
  )
}

is_local_tool_definition <- function(x) {
  inherits(x, "mcplite_tool") && is.function(x)
}

is_local_tool_type <- function(x) {
  inherits(x, "mcplite_tool_type")
}

is_supported_tool_type <- function(x) {
  is_local_tool_type(x) || is_ellmer_tool_type(x)
}

normalize_tool_argument_types <- function(arguments) {
  if (length(arguments) == 0) {
    return(named_list())
  }

  bad <- !vapply(arguments, is_supported_tool_type, logical(1))
  if (any(bad)) {
    stop(
      "Each entry in `arguments` must be a mcplite or compatible ellmer type helper.",
      call. = FALSE
    )
  }

  arguments[!vapply(arguments, is_ignored_tool_type, logical(1))]
}

normalize_tool_input_schema <- function(arguments) {
  if (inherits(arguments, "mcplite_tool_type_schema")) {
    schema <- schema_from_tool_type(arguments)
    schema <- normalize_json_object(schema, "arguments")
    if (!identical(schema[["type"]], "object")) {
      stop(
        paste(
          "`arguments = type_from_schema(...)` must have direct root",
          "`type = \"object\"`."
        ),
        call. = FALSE
      )
    }
  } else {
    if (!is_named_or_empty_list(arguments)) {
      stop(
        paste(
          "`arguments` must be a named list of type helpers or a complete",
          "object-root schema from `type_from_schema()`."
        ),
        call. = FALSE
      )
    }
    schema <- schema_from_properties(normalize_tool_argument_types(arguments))
  }

  check_schema_containers(schema, "arguments")
  check_json_serializable(schema, "arguments")
  schema
}

check_schema_containers <- function(schema, arg = "output_schema") {
  if (is.function(schema) || is.environment(schema)) {
    stop(
      paste(
        sprintf("`%s` must be JSON serializable;", arg),
        "functions and environments are not JSON values."
      ),
      call. = FALSE
    )
  }

  # Classed lists can override JSON container shape, as data frames do.
  if (is.list(schema) && is.object(schema)) {
    stop(
      sprintf("`%s` contains an unsupported classed list container.", arg),
      call. = FALSE
    )
  }

  if (is.list(schema)) {
    for (value in schema) {
      check_schema_containers(value, arg)
    }
  }

  invisible(schema)
}

normalize_tool_output_schema <- function(output_schema) {
  if (is.null(output_schema)) {
    return(NULL)
  }

  if (!is_supported_tool_type(output_schema)) {
    stop(
      "`output_schema` must be a mcplite or compatible ellmer type helper.",
      call. = FALSE
    )
  }

  schema <- schema_from_tool_type(output_schema)
  schema <- normalize_json_object(schema, "output_schema")

  check_schema_containers(schema, "output_schema")
  check_json_serializable(schema, "output_schema")
  schema
}
