# mcplite

<!-- badges: start -->
[![R-CMD-check](https://github.com/tosidata/mcplite/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tosidata/mcplite/actions/workflows/R-CMD-check.yaml)
[![CRAN status](https://www.r-pkg.org/badges/version/mcplite)](https://CRAN.R-project.org/package=mcplite)
<!-- badges: end -->

`mcplite` exposes R functions as [Model Context Protocol](https://modelcontextprotocol.io/)
(MCP) tools through a lightweight standard-input/standard-output (stdio)
server. Use it when a local MCP client needs to call R code for data lookups,
calculations, report helpers, or automation.

## Installation

Install the released version from CRAN:

```r
install.packages("mcplite")
```

Install the development version from GitHub:

```r
pak::pak("tosidata/mcplite")
```

## Quick start

Save a complete server definition as `server.R`:

```r
library(mcplite)

add_numbers <- tool(
  function(x, y) {
    x + y
  },
  name = "add_numbers",
  description = "Add two numbers and return the result.",
  arguments = list(
    x = type_number("First number."),
    y = type_number("Second number.")
  )
)

mcp_server(list(add_numbers))
```

Configure your MCP client to launch the script. The `command` must resolve to
the `Rscript` executable. If `Rscript` is not discoverable, run
`Sys.which("Rscript")` in R and use the returned path as the client's `command`.
Keep the server script path absolute too. A Claude Desktop-style configuration
looks like this:

```json
{
  "mcpServers": {
    "r-tools": {
      "command": "Rscript",
      "args": [
        "--vanilla",
        "/absolute/path/to/server.R"
      ]
    }
  }
}
```

Restart the client and check that it discovers `add_numbers`. As a first call,
ask it to run `add_numbers` with `x = 2` and `y = 3`; the result should be `5`.

`mcp_server()` starts serving immediately and runs until standard input closes,
so launch it through the MCP client rather than from an interactive R console.

## Supported scope

`mcplite` is a tools-only, stdio-only MCP server. It supports modern MCP
`2026-07-28` and legacy MCP `2024-11-05`, `2025-06-18`, and `2025-11-25`. The
same server definition works with modern and legacy clients.

Tools can return ordinary R values, rich MCP content, structured results, and
tool-level errors. Compatible `ellmer::tool()` definitions can also be supplied
directly.

The package focuses on local, client-launched tools. It does not provide an HTTP
transport, prompt or resource endpoints, or multi-round-trip MCP feature
families. Tools can still include supported embedded resources and resource
links in their results.

## Learn more

The [getting-started article](https://tosidata.github.io/mcplite/articles/mcplite.html)
covers complete JSON schemas, rich and structured results, version-specific
authoring behavior, `ellmer` interoperability, tracing, and safety.

See `?tool` and `help("tool-types", package = "mcplite")` for tool definitions
and schemas, `?tool_result` and
`help("content-blocks", package = "mcplite")` for rich results, and
`?mcp_server` for server behavior.
