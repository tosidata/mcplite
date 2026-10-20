#' mcplite: Lightweight stdio MCP server for R
#'
#' Expose R functions as tools for a local Model Context Protocol (MCP) client.
#' Define tools, save them in a script ending with [mcp_server()], and configure
#' the client to launch that script with `Rscript --vanilla` and an absolute
#' script path. The server blocks until standard input closes.
#'
#' @section Define tools and return results:
#' Use `mcplite::tool()` with the [tool-types] helpers to describe arguments.
#' Tools remain directly callable R functions. Return ordinary R values for
#' text conversion, or [tool_result()] with [content_text()] and other
#' [content-blocks] constructors for structured or rich output. See
#' [mcplite-results] for exact return-value mappings and payload JSON options.
#'
#' Schemas do not validate values or enforce permissions. Tools own domain
#' validation, authorization, safe side effects, and output limits. Keep stdout
#' exclusively for MCP protocol messages; use stderr for diagnostics.
#'
#' @section Scope and next steps:
#' `mcplite` is tools-only and stdio-only; embedded resources and resource links
#' in results do not provide resource endpoints. See [mcp_server()] for server
#' use, supported protocol versions, and optional tracing. Compatible
#' `ellmer::tool()` objects are accepted, but ellmer is not required.
#'
#' Website guides: [Get started](https://tosidata.github.io/mcplite/articles/mcplite.html),
#' [Write tools](https://tosidata.github.io/mcplite/articles/writing-tools.html),
#' and [Return results](https://tosidata.github.io/mcplite/articles/returning-results.html).
#'
#' @name mcplite
#' @aliases mcplite-package
"_PACKAGE"
