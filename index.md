# mcplite

`mcplite` exposes R functions as [Model Context
Protocol](https://modelcontextprotocol.io/) (MCP) tools through a
lightweight standard-input/standard-output (stdio) server. Use it when a
local MCP client needs to call R code for data lookups, calculations,
report helpers, or automation.

## Installation

Install the released version from CRAN:

``` r

install.packages("mcplite")
```

Install the development version from GitHub:

``` r

pak::pak("tosidata/mcplite")
```

## Quick start

Save a complete server definition as `server.R`:

``` r

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

Configure your MCP client to launch the script. The `command` must
resolve to the `Rscript` executable. If `Rscript` is not discoverable,
run `Sys.which("Rscript")` in R and use the returned path as the
client’s `command`. Keep the server script path absolute too. A Claude
Desktop-style configuration looks like this:

``` json
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

Restart the client and check that it discovers `add_numbers`. As a first
call, ask it to run `add_numbers` with `x = 2` and `y = 3`; the result
should be `5`.

[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
starts serving immediately and runs until standard input closes, so
launch it through the MCP client rather than from an interactive R
console.

## Supported scope

`mcplite` is a tools-only, stdio-only MCP server. It supports modern MCP
`2026-07-28` and legacy MCP `2024-11-05`, `2025-06-18`, and
`2025-11-25`. The same server definition works with modern and legacy
clients.

Tools can return ordinary R values, rich MCP content, structured
results, and tool-level errors. Compatible
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definitions can also be supplied directly.

The package focuses on local, client-launched tools. It does not provide
an HTTP transport, prompt or resource endpoints, or multi-round-trip MCP
feature families. Tools can still include supported embedded resources
and resource links in their results.

## Learn more

Choose the next task:

- [Get
  started](https://tosidata.github.io/mcplite/articles/mcplite.html):
  save a server script, connect a client, and make a first call.
- [Write
  tools](https://tosidata.github.io/mcplite/articles/writing-tools.html):
  describe arguments, handle defaults and arrays, and report failures.
- [Return
  results](https://tosidata.github.io/mcplite/articles/returning-results.html):
  choose ordinary values, structured content, or rich content blocks.

For installed help, start with
[`?mcplite`](https://tosidata.github.io/mcplite/reference/mcplite.md).
See [`?tool`](https://tosidata.github.io/mcplite/reference/tool.md) and
[`help("tool-types", package = "mcplite")`](https://tosidata.github.io/mcplite/reference/tool-types.md)
for definitions and schemas,
[`help("mcplite-results", package = "mcplite")`](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact return-value mappings and payload options, and
[`?mcp_server`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
for server use, compatibility, and tracing.
