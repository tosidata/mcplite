# Get started with mcplite

Connect a local MCP client to an R tool and make a first call. You need
R, `mcplite`, and a client that can launch a stdio MCP server.

## 1. Install mcplite

Install the released version from CRAN:

``` r

install.packages("mcplite")
```

Install the development version from GitHub:

``` r

pak::pak("tosidata/mcplite")
```

## 2. Save a complete server script

Save the following as `server.R`. It defines one inventory tool and then
starts the server.

``` r

library(mcplite)

inventory_status <- tool(
  function(item) {
    stock <- c(apples = 12L, coffee = 0L, tea = 5L)

    if (!item %in% names(stock)) {
      stop("`item` must be apples, coffee, or tea.", call. = FALSE)
    }

    list(
      item = item,
      count = unname(stock[[item]])
    )
  },
  name = "inventory_status",
  description = "Report the local inventory count for a known item.",
  arguments = list(
    item = type_enum(
      c("apples", "coffee", "tea"),
      "Item whose inventory should be checked."
    )
  )
)

mcp_server(list(inventory_status))
```

A tool combines an R function with a client-facing name, description,
and argument schema. Schemas describe inputs; they do not validate them.
The function checks which items it can look up.

[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
blocks the R process while it serves requests. Put it at the end of a
client-launched script, after all tools have been defined or sourced.

## 3. Configure the client

Add a server entry to your MCP client’s configuration. The `command`
must resolve to the `Rscript` executable. GUI-launched clients may not
inherit your shell’s search path; if `Rscript` is not discoverable, run
`Sys.which("Rscript")` in R and use the returned absolute path as the
client’s `command`. Replace the server path below with the absolute path
to the `server.R` file you saved. The script path must be absolute
because the client’s working directory is not guaranteed.

``` json
{
  "mcpServers": {
    "r-inventory": {
      "command": "Rscript",
      "args": [
        "--vanilla",
        "/absolute/path/to/server.R"
      ]
    }
  }
}
```

Configuration file names and locations vary by client; use the client’s
MCP server configuration instructions.

## 4. Restart the client and use the tool

Restart the client so it launches the new server. The client should then
list `inventory_status` as an available tool. Ask it to check the local
inventory for coffee. Success means the result identifies `coffee` with
a count of `0`; exact presentation varies by client.

The client and server communicate over standard input and output. The
server exits when standard input closes. Keep stdout exclusively for MCP
protocol traffic: do not write diagnostic output or telemetry there. Use
stderr for local diagnostics.

## Run with appropriate permissions

Schemas are not authorization or sandboxing. Each tool is responsible
for permission checks, credential handling, safe side effects, and
appropriate output limits. Run the server with only the operating-system
and data permissions its tools need.

## Next steps

- [Write
  tools](https://tosidata.github.io/mcplite/articles/writing-tools.md)
  to handle arguments, defaults, arrays, and failures, then describe
  more complex inputs.
- [Return
  results](https://tosidata.github.io/mcplite/articles/returning-results.md)
  to add structured data or rich content to a tool.
- See
  [`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
  for server scope, protocol compatibility, and optional OpenTelemetry
  tracing.
