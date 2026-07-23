#' Construct protocol-native MCP tool results
#'
#' `tool_result()` is the explicit opt-in boundary for returning protocol-native
#' MCP results. Its `content` must be created with one of the `content_*()`
#' constructors; ordinary R values, including bare lists and JSON strings,
#' retain the legacy single-text-block conversion used by [tool()].
#'
#' When `structured_content` is supplied and `content` is omitted,
#' `tool_result()` generates exactly one JSON text fallback block. Explicitly
#' supplied content is preserved as-is and no fallback is appended. Structured
#' content and tool output schemas are sent only to clients using MCP
#' `2025-06-18` or later; older clients receive the generated text fallback.
#'
#' @param content One content block created by a `content_*()` constructor, or
#'   an ordered list of such blocks. Omitting `content` permits automatic text
#'   fallback generation from `structured_content`; explicit `content = list()`
#'   suppresses fallback and is invalid.
#' @param structured_content Optional named list representing a JSON object.
#'   An empty object is allowed. `mcplite` does not validate this value against
#'   a tool's advertised output schema.
#' @param is_error Whether the result reports a tool error.
#' @param meta Optional named result metadata. MCP wire names such as `_meta`
#'   are created only during serialization.
#'
#' @return A protocol-native tool result for return from a tool function.
#' @seealso [content_text()], [content_image()], [content_audio()],
#'   [content_resource_link()], and [content_resource()].
#' @export
#'
#' @examples
#' tool_result(content_text("Done."))
#'
#' tool_result(
#'   content = list(
#'     content_text("Generated the plot."),
#'     content_image("base64-data", "image/png")
#'   )
#' )
#'
#' tool_result(structured_content = list(ok = TRUE, count = 2L))
tool_result <- function(
  content = list(),
  structured_content = NULL,
  is_error = FALSE,
  meta = list()
) {
  content_was_missing <- missing(content)
  structured_content <- normalize_json_object(
    structured_content,
    "structured_content",
    allow_null = TRUE
  )

  if (content_was_missing) {
    content <- if (!is.null(structured_content)) {
      list(content_text(to_json(structured_content)))
    } else {
      list()
    }
  } else if (inherits(content, "mcplite_content")) {
    content <- list(content)
  }

  new_tool_result(
    content = content,
    structured_content = structured_content,
    is_error = is_error,
    meta = meta
  )
}

#' Construct protocol-native MCP content blocks
#'
#' These constructors create the only content-block objects accepted by
#' [tool_result()]. All R-facing names use `snake_case`; MCP names such as
#' `mimeType` and `_meta` are created only when a result is serialized.
#'
#' Image, audio, and resource blob data must already be scalar base64 strings.
#' The constructors do not read files, download URLs, infer MIME types, encode,
#' decode, or validate base64 data, or invent resource URIs. Tool authors own
#' payload integrity, accurate MIME types, meaningful URIs, authorization,
#' sanitization, and payload size decisions.
#'
#' Resource links only transport an author-supplied URI. `mcplite` remains a
#' tools-only server and does not make that URI readable or implement
#' `resources/read`. Embedded resources are self-contained content blocks.
#'
#' @param text A single text string. For `content_resource()`, the resource text
#'   payload; exactly one of `text` or `blob` must be supplied.
#' @param data A scalar base64 string containing inline image or audio data.
#' @param mime_type A single MIME type string. Optional for resources and
#'   resource links.
#' @param uri A single non-empty author-supplied resource URI.
#' @param name A single non-empty resource-link name.
#' @param title Optional resource-link display title.
#' @param description Optional resource-link description.
#' @param size Optional non-negative whole-number resource size in bytes.
#' @param blob A scalar base64 string containing an embedded resource payload;
#'   exactly one of `text` or `blob` must be supplied.
#' @param annotations Optional named MCP annotations. Known R-facing fields are
#'   `audience`, `priority`, and `last_modified`; named extension fields are
#'   preserved when serializable.
#' @param meta Optional named outer content-block metadata. For
#'   `content_resource()`, metadata is not duplicated into the inner resource
#'   contents object.
#'
#' @return A validated content block for use in [tool_result()].
#' @name content-blocks
NULL

#' @rdname content-blocks
#' @export
content_text <- function(text, annotations = list(), meta = list()) {
  check_scalar_string(text, "text")
  new_content_block(
    "text",
    text = text,
    annotations = annotations,
    meta = meta
  )
}

#' @rdname content-blocks
#' @export
content_image <- function(
  data,
  mime_type,
  annotations = list(),
  meta = list()
) {
  check_scalar_string(data, "data")
  check_nonempty_scalar_string(mime_type, "mime_type")
  new_content_block(
    "image",
    data = data,
    mime_type = mime_type,
    annotations = annotations,
    meta = meta
  )
}

#' @rdname content-blocks
#' @export
content_audio <- function(
  data,
  mime_type,
  annotations = list(),
  meta = list()
) {
  check_scalar_string(data, "data")
  check_nonempty_scalar_string(mime_type, "mime_type")
  new_content_block(
    "audio",
    data = data,
    mime_type = mime_type,
    annotations = annotations,
    meta = meta
  )
}

#' @rdname content-blocks
#' @export
content_resource_link <- function(
  uri,
  name,
  title = NULL,
  description = NULL,
  mime_type = NULL,
  size = NULL,
  annotations = list(),
  meta = list()
) {
  check_nonempty_scalar_string(uri, "uri")
  check_nonempty_scalar_string(name, "name")
  check_optional_scalar_string(title, "title")
  check_optional_scalar_string(description, "description")
  check_optional_nonempty_scalar_string(mime_type, "mime_type")

  if (
    !is.null(size) &&
      (!is_scalar_numeric(size) ||
        !is.finite(size) ||
        size < 0 ||
        size != floor(size))
  ) {
    stop("`size` must be a non-negative whole number or NULL.", call. = FALSE)
  }

  new_content_block(
    "resource_link",
    uri = uri,
    name = name,
    title = title,
    description = description,
    mime_type = mime_type,
    size = size,
    annotations = annotations,
    meta = meta
  )
}

#' @rdname content-blocks
#' @export
content_resource <- function(
  uri,
  text = NULL,
  blob = NULL,
  mime_type = NULL,
  annotations = list(),
  meta = list()
) {
  check_nonempty_scalar_string(uri, "uri")
  check_optional_nonempty_scalar_string(mime_type, "mime_type")

  if (is.null(text) == is.null(blob)) {
    stop("Supply exactly one of `text` or `blob`.", call. = FALSE)
  }

  if (!is.null(text)) {
    check_scalar_string(text, "text")
  }
  if (!is.null(blob)) {
    check_scalar_string(blob, "blob")
  }

  new_content_block(
    "resource",
    uri = uri,
    text = text,
    blob = blob,
    mime_type = mime_type,
    annotations = annotations,
    meta = meta
  )
}

check_nonempty_scalar_string <- function(x, arg) {
  check_scalar_string(x, arg)
  if (!nzchar(x)) {
    stop(sprintf("`%s` must be a non-empty string.", arg), call. = FALSE)
  }
}

check_optional_nonempty_scalar_string <- function(x, arg) {
  if (!is.null(x)) {
    check_nonempty_scalar_string(x, arg)
  }
}

normalize_json_object <- function(x, arg, allow_null = FALSE) {
  if (allow_null && is.null(x)) {
    return(NULL)
  }

  if (
    !is.list(x) ||
      is.object(x) ||
      (length(x) > 0 &&
        (is.null(names(x)) ||
          any(!nzchar(names(x))) ||
          anyDuplicated(names(x))))
  ) {
    stop(sprintf("`%s` must be a named JSON object.", arg), call. = FALSE)
  }

  x <- named_or_empty(x)
  check_json_serializable(x, arg)
  x
}

check_json_serializable <- function(x, arg) {
  tryCatch(
    to_json(x),
    error = function(cnd) {
      stop(
        sprintf(
          "`%s` must be JSON serializable: %s",
          arg,
          conditionMessage(cnd)
        ),
        call. = FALSE
      )
    }
  )
  invisible(x)
}

normalize_content_annotations <- function(annotations) {
  annotations <- normalize_json_object(annotations, "annotations")

  if ("lastModified" %in% names(annotations)) {
    stop(
      "Use the R-facing annotation name `last_modified`, not `lastModified`.",
      call. = FALSE
    )
  }

  audience <- annotations$audience
  if (
    !is.null(audience) &&
      (!is.character(audience) ||
        length(audience) == 0 ||
        anyNA(audience) ||
        !all(audience %in% c("user", "assistant")))
  ) {
    stop(
      "`annotations$audience` must contain only `user` and `assistant`.",
      call. = FALSE
    )
  }
  if (!is.null(audience)) {
    annotations$audience <- as.list(audience)
  }

  priority <- annotations$priority
  if (
    !is.null(priority) &&
      (!is_scalar_numeric(priority) ||
        !is.finite(priority) ||
        priority < 0 ||
        priority > 1)
  ) {
    stop("`annotations$priority` must be a number from 0 to 1.", call. = FALSE)
  }

  check_optional_scalar_string(
    annotations$last_modified,
    "annotations$last_modified"
  )
  check_json_serializable(annotations, "annotations")
  annotations
}

new_content_block <- function(type, ..., annotations = list(), meta = list()) {
  annotations <- normalize_content_annotations(annotations)
  meta <- normalize_json_object(meta, "meta")

  structure(
    c(
      list(type = type),
      list(...),
      list(annotations = annotations, meta = meta)
    ),
    class = c(paste0("mcplite_content_", type), "mcplite_content")
  )
}

has_exact_fields <- function(x, fields) {
  is.list(x) &&
    length(x) == length(fields) &&
    !is.null(names(x)) &&
    !anyDuplicated(names(x)) &&
    setequal(names(x), fields)
}

normalize_content_block <- function(x) {
  if (
    !inherits(x, "mcplite_content") ||
      !is.list(x) ||
      !is_scalar_character(x$type) ||
      !x$type %in% c("text", "image", "audio", "resource_link", "resource") ||
      !inherits(x, paste0("mcplite_content_", x$type))
  ) {
    stop(
      "`content` must contain blocks created by `content_*()` constructors.",
      call. = FALSE
    )
  }

  fields <- switch(
    x$type,
    text = c("type", "text", "annotations", "meta"),
    image = c("type", "data", "mime_type", "annotations", "meta"),
    audio = c("type", "data", "mime_type", "annotations", "meta"),
    resource_link = c(
      "type",
      "uri",
      "name",
      "title",
      "description",
      "mime_type",
      "size",
      "annotations",
      "meta"
    ),
    resource = c(
      "type",
      "uri",
      "text",
      "blob",
      "mime_type",
      "annotations",
      "meta"
    )
  )

  if (!has_exact_fields(x, fields)) {
    stop("A `content_*()` block has invalid canonical fields.", call. = FALSE)
  }

  annotations <- x$annotations
  if (is.list(annotations) && is.list(annotations$audience)) {
    annotations$audience <- unlist(
      annotations$audience,
      recursive = FALSE,
      use.names = FALSE
    )
  }

  switch(
    x$type,
    text = content_text(
      x$text,
      annotations = annotations,
      meta = x$meta
    ),
    image = content_image(
      x$data,
      x$mime_type,
      annotations = annotations,
      meta = x$meta
    ),
    audio = content_audio(
      x$data,
      x$mime_type,
      annotations = annotations,
      meta = x$meta
    ),
    resource_link = content_resource_link(
      x$uri,
      x$name,
      title = x$title,
      description = x$description,
      mime_type = x$mime_type,
      size = x$size,
      annotations = annotations,
      meta = x$meta
    ),
    resource = content_resource(
      x$uri,
      text = x$text,
      blob = x$blob,
      mime_type = x$mime_type,
      annotations = annotations,
      meta = x$meta
    )
  )
}

normalize_tool_result_content <- function(content) {
  if (!is.list(content) || length(content) == 0) {
    stop(
      paste(
        "`content` must contain at least one block created by a",
        "`content_*()` constructor."
      ),
      call. = FALSE
    )
  }

  unname(lapply(content, normalize_content_block))
}

new_tool_result <- function(
  content,
  structured_content = NULL,
  is_error = FALSE,
  meta = named_list()
) {
  if (!is.logical(is_error) || length(is_error) != 1 || is.na(is_error)) {
    stop("`is_error` must be TRUE or FALSE.", call. = FALSE)
  }

  structure(
    list(
      content = normalize_tool_result_content(content),
      structured_content = normalize_json_object(
        structured_content,
        "structured_content",
        allow_null = TRUE
      ),
      is_error = is_error,
      meta = normalize_json_object(meta, "meta")
    ),
    class = "mcplite_tool_result"
  )
}

new_text_tool_result <- function(text, is_error = FALSE) {
  new_tool_result(
    content = list(content_text(text)),
    is_error = is_error
  )
}

is_tool_result <- function(result) {
  inherits(result, "mcplite_tool_result")
}

normalize_inherited_tool_result <- function(result) {
  fields <- c("content", "structured_content", "is_error", "meta")
  if (!has_exact_fields(result, fields)) {
    stop("Invalid canonical `mcplite_tool_result` fields.", call. = FALSE)
  }

  new_tool_result(
    content = result$content,
    structured_content = result$structured_content,
    is_error = result$is_error,
    meta = result$meta
  )
}
