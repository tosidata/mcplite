is_tool_definition <- function(x) {
  is_local_tool_definition(x) || is_ellmer_tool_definition(x)
}

is_ellmer_tool_definition <- function(x) {
  inherits(x, "ellmer::ToolDef") && is.function(x)
}

is_ellmer_tool_type <- function(x) {
  inherits(x, "ellmer::Type")
}

tool_definition_name <- function(tool) {
  if (is_local_tool_definition(tool)) {
    return(attr(tool, "mcplite_tool")$name)
  }

  attr(tool, "name")
}

tool_definition_description <- function(tool) {
  if (is_local_tool_definition(tool)) {
    return(attr(tool, "mcplite_tool")$description)
  }

  attr(tool, "description")
}

tool_definition_arguments <- function(tool) {
  if (is_local_tool_definition(tool)) {
    return(attr(tool, "mcplite_tool")$arguments)
  }

  attr(tool, "arguments")
}

tool_definition_annotations <- function(tool) {
  if (is_local_tool_definition(tool)) {
    return(attr(tool, "mcplite_tool")$annotations)
  }

  attr(tool, "annotations") %||% named_list()
}

tool_definition_output_schema <- function(tool) {
  if (is_local_tool_definition(tool)) {
    return(attr(tool, "mcplite_tool")$output_schema)
  }

  NULL
}

input_schema_from_tool <- function(tool) {
  arguments <- tool_definition_arguments(tool)

  if (inherits(arguments, "ellmer::TypeObject")) {
    return(schema_from_tool_type(arguments))
  }

  schema_from_properties(arguments)
}

tool_as_mcp_definition <- function(tool, protocol_version) {
  out <- list(
    name = tool_definition_name(tool),
    description = tool_definition_description(tool),
    inputSchema = input_schema_from_tool(tool)
  )

  annotations <- tool_definition_annotations(tool)
  if (length(annotations) > 0) {
    out$annotations <- annotations
  }

  output_schema <- tool_definition_output_schema(tool)
  if (
    protocol_version_gte(protocol_version, "2025-06-18") &&
      !is.null(output_schema)
  ) {
    out$outputSchema <- output_schema
  }

  out
}

schema_from_properties <- function(properties) {
  property_schemas <- lapply(properties, schema_from_tool_type)
  property_schemas <- property_schemas[
    !vapply(property_schemas, is.null, logical(1))
  ]
  required <- names(properties)[
    vapply(properties, tool_type_required, logical(1)) &
      !vapply(properties, is_ignored_tool_type, logical(1))
  ]

  compact_nulls(list(
    type = "object",
    properties = named_or_empty(property_schemas),
    required = if (length(required) > 0) as.list(required),
    additionalProperties = FALSE
  ))
}

schema_from_tool_type <- function(type) {
  if (is_ignored_tool_type(type)) {
    return(NULL)
  }

  if (inherits(type, "mcplite_tool_type_schema")) {
    return(type$schema)
  }

  if (inherits(type, "ellmer::TypeJsonSchema")) {
    return(attr(type, "json"))
  }

  kind <- tool_type_kind(type)
  schema <- switch(
    kind,
    boolean = list(type = "boolean"),
    integer = list(type = "integer"),
    number = list(type = "number"),
    string = list(type = "string"),
    enum = list(
      type = enum_json_type(tool_type_values(type)),
      enum = tool_type_values(type)
    ),
    array = list(
      type = "array",
      items = schema_from_tool_type(tool_type_items(type))
    ),
    object = object_schema_from_type(type),
    stop("Unsupported tool type.", call. = FALSE)
  )

  compact_nulls(c(
    schema,
    list(description = tool_type_description(type))
  ))
}

object_schema_from_type <- function(type) {
  properties <- tool_type_properties(type)
  property_schemas <- lapply(properties, schema_from_tool_type)
  property_schemas <- property_schemas[
    !vapply(property_schemas, is.null, logical(1))
  ]
  required <- names(properties)[
    vapply(properties, tool_type_required, logical(1)) &
      !vapply(properties, is_ignored_tool_type, logical(1))
  ]

  compact_nulls(list(
    type = "object",
    properties = named_or_empty(property_schemas),
    required = if (length(required) > 0) as.list(required),
    additionalProperties = tool_type_additional_properties(type)
  ))
}

tool_type_kind <- function(type) {
  if (is_local_tool_type(type)) {
    return(type$kind)
  }

  if (inherits(type, "ellmer::TypeBasic")) {
    return(attr(type, "type"))
  }
  if (inherits(type, "ellmer::TypeEnum")) {
    return("enum")
  }
  if (inherits(type, "ellmer::TypeArray")) {
    return("array")
  }
  if (inherits(type, "ellmer::TypeObject")) {
    return("object")
  }

  stop("Unsupported ellmer tool type.", call. = FALSE)
}

tool_type_description <- function(type) {
  if (is_local_tool_type(type)) {
    return(type$description)
  }

  attr(type, "description")
}

tool_type_required <- function(type) {
  if (is_local_tool_type(type)) {
    return(isTRUE(type$required))
  }

  isTRUE(attr(type, "required"))
}

tool_type_values <- function(type) {
  if (is_local_tool_type(type)) {
    return(type$values)
  }

  as.list(attr(type, "values"))
}

tool_type_items <- function(type) {
  if (is_local_tool_type(type)) {
    return(type$items)
  }

  attr(type, "items")
}

tool_type_properties <- function(type) {
  if (is_local_tool_type(type)) {
    return(type$properties)
  }

  attr(type, "properties") %||% named_list()
}

tool_type_additional_properties <- function(type) {
  if (is_local_tool_type(type)) {
    return(isTRUE(type$additional_properties))
  }

  isTRUE(attr(type, "additional_properties"))
}

is_ignored_tool_type <- function(type) {
  inherits(type, "mcplite_tool_type_ignore") ||
    inherits(type, "ellmer::TypeIgnore")
}

enum_json_type <- function(values) {
  unlisted_values <- unlist(values, recursive = FALSE, use.names = FALSE)

  if (is.character(unlisted_values)) {
    "string"
  } else if (is.integer(unlisted_values)) {
    "integer"
  } else if (is.numeric(unlisted_values)) {
    "number"
  } else if (is.logical(unlisted_values)) {
    "boolean"
  } else {
    NULL
  }
}

named_or_empty <- function(x) {
  if (length(x) == 0) {
    return(named_list())
  }

  x
}

compact_nulls <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

is_ellmer_content_tool_result <- function(result) {
  inherits(result, "ellmer::ContentToolResult")
}

is_ellmer_content <- function(result) {
  inherits(result, "ellmer::Content")
}

content_tool_result_error_text <- function(error) {
  if (inherits(error, "condition")) {
    return(conditionMessage(error))
  }

  as.character(error)[[1]]
}

ellmer_content_as_block <- function(content) {
  if (inherits(content, "ellmer::ContentText")) {
    return(content_text(content@text))
  }

  if (inherits(content, "ellmer::ContentImageInline")) {
    return(content_image(data = content@data, mime_type = content@type))
  }

  class_name <- class(content)[[1]]
  stop(
    paste0(
      "Unsupported ellmer content `",
      class_name,
      "`. Return an explicit ",
      "mcplite::tool_result() using content_text(), content_image(), ",
      "content_resource_link(), or content_resource() as appropriate."
    ),
    call. = FALSE
  )
}

as_tool_result <- function(result) {
  if (is_tool_result(result)) {
    return(normalize_inherited_tool_result(result))
  }

  if (is_ellmer_content_tool_result(result)) {
    error <- result@error
    if (!is.null(error)) {
      return(new_text_tool_result(
        content_tool_result_error_text(error),
        is_error = TRUE
      ))
    }

    result <- result@value
  }

  if (is_ellmer_content(result)) {
    return(new_tool_result(
      content = list(ellmer_content_as_block(result))
    ))
  }

  if (is.list(result)) {
    ellmer_content <- vapply(result, is_ellmer_content, logical(1))
    if (any(ellmer_content)) {
      if (!all(ellmer_content)) {
        stop(
          paste(
            "Lists containing ellmer content must be made entirely of",
            "supported ellmer content values."
          ),
          call. = FALSE
        )
      }

      return(new_tool_result(
        content = lapply(result, ellmer_content_as_block)
      ))
    }
  }

  new_text_tool_result(tool_value_to_text(result))
}

tool_value_to_text <- function(value) {
  if (is.null(value)) {
    return(to_json(named_list()))
  }

  if (is.character(value)) {
    return(paste(value, collapse = "\n"))
  }

  tryCatch(
    to_json(value),
    error = function(cnd) {
      stop(
        sprintf(
          "Failed to convert tool result to text: %s",
          conditionMessage(cnd)
        ),
        call. = FALSE
      )
    }
  )
}

protocol_supports_content_type <- function(protocol_version, type) {
  protocol_version_gte(protocol_version, "2025-06-18") ||
    type %in% c("text", "image", "resource")
}

annotations_as_mcp <- function(annotations, protocol_version) {
  out <- annotations
  last_modified <- out$last_modified
  out$last_modified <- NULL

  if (
    protocol_version_gte(protocol_version, "2025-06-18") &&
      !is.null(last_modified)
  ) {
    out$lastModified <- last_modified
  }

  out
}

content_block_as_mcp <- function(content, protocol_version) {
  out <- switch(
    content$type,
    text = list(type = "text", text = content$text),
    image = list(
      type = "image",
      data = content$data,
      mimeType = content$mime_type
    ),
    audio = list(
      type = "audio",
      data = content$data,
      mimeType = content$mime_type
    ),
    resource_link = compact_nulls(list(
      type = "resource_link",
      uri = content$uri,
      name = content$name,
      title = content$title,
      description = content$description,
      mimeType = content$mime_type,
      size = content$size
    )),
    resource = list(
      type = "resource",
      resource = compact_nulls(list(
        uri = content$uri,
        mimeType = content$mime_type,
        text = content$text,
        blob = content$blob
      ))
    )
  )

  if (length(content$annotations) > 0) {
    out$annotations <- annotations_as_mcp(
      content$annotations,
      protocol_version
    )
  }

  if (
    protocol_version_gte(protocol_version, "2025-06-18") &&
      length(content$meta) > 0
  ) {
    out$`_meta` <- content$meta
  }

  out
}

tool_result_as_mcp <- function(result, protocol_version) {
  content_types <- vapply(result$content, `[[`, character(1), "type")
  supported <- vapply(
    content_types,
    function(type) protocol_supports_content_type(protocol_version, type),
    logical(1)
  )

  if (any(!supported)) {
    stop(
      sprintf(
        "MCP protocol %s does not support tool-result content type(s): %s.",
        protocol_version,
        paste(unique(content_types[!supported]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out <- list(
    content = lapply(
      result$content,
      content_block_as_mcp,
      protocol_version = protocol_version
    ),
    isError = result$is_error
  )

  if (
    protocol_version_gte(protocol_version, "2025-06-18") &&
      !is.null(result$structured_content)
  ) {
    out$structuredContent <- result$structured_content
  }

  if (length(result$meta) > 0) {
    out$`_meta` <- result$meta
  }

  # Force serialization while the tools/call error boundary can still convert
  # failures into a normal MCP tool-call error result.
  to_json(out)
  out
}

as_tool_call_response <- function(id, result, protocol_version) {
  result <- as_tool_result(result)
  jsonrpc_response(
    id,
    result = tool_result_as_mcp(result, protocol_version)
  )
}
