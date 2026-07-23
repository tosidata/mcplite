`%||%` <- function(x, y) {
  if (is.null(x)) {
    y
  } else {
    x
  }
}

named_list <- function(...) {
  out <- list(...)

  if (length(out) == 0) {
    out <- structure(list(), names = character())
  }

  out
}

drop_nulls <- function(x) {
  is_null <- vapply(x, is.null, logical(1))
  keep_id <- rep(FALSE, length(x))

  if (!is.null(names(x))) {
    keep_id <- names(x) == "id"
  }

  x[!is_null | keep_id]
}

#' @importFrom jsonlite toJSON
to_json <- function(x) {
  toJSON(x, auto_unbox = TRUE, null = "null")
}

is_scalar_character <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

empty_named_list <- function(x) {
  is.list(x) && length(x) == 0 && !is.null(names(x))
}

is_named_list <- function(x) {
  is.list(x) && (!is.null(names(x)) || empty_named_list(x))
}

compact <- function(x) {
  Filter(length, x)
}

package_version_string <- function() {
  installed <- tryCatch(
    as.character(utils::packageVersion("mcplite")),
    error = function(cnd) {
      NULL
    }
  )

  if (!is.null(installed)) {
    return(installed)
  }

  description_path <- file.path(getwd(), "DESCRIPTION")

  if (file.exists(description_path)) {
    return(unname(read.dcf(description_path, fields = "Version")[1, 1]))
  }

  "0.0.0.9000"
}
