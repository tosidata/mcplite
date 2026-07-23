as_tool_registry <- function(tools) {
  if (is_tool_definition(tools)) {
    tools <- list(tools)
  }

  if (!is.list(tools) || !all(vapply(tools, is_tool_definition, logical(1)))) {
    stop(
      paste(
        "`tools` must be a mcplite::tool() definition or a list of",
        "mcplite::tool() definitions. Compatible ellmer::tool() objects are",
        "also accepted when supplied directly."
      ),
      call. = FALSE
    )
  }

  names <- vapply(tools, tool_definition_name, character(1))
  duplicates <- unique(names[duplicated(names)])

  if (length(duplicates) > 0) {
    stop(
      sprintf(
        "Tool names must be unique. Duplicated names: %s",
        paste(duplicates, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  list(
    # Keep feature families grouped here so prompts/resources can be added later
    # without changing the server dispatch boundary.
    tools = stats::setNames(tools, names)
  )
}

registry_tools_as_mcp <- function(registry, protocol_version) {
  lapply(
    unname(registry$tools),
    tool_as_mcp_definition,
    protocol_version = protocol_version
  )
}

registry_tool <- function(registry, name) {
  registry$tools[[name]]
}
