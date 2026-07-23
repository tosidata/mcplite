# Get started with mcplite

``` r

library(mcplite)
```

This article shows the complete first-use workflow: install `mcplite`,
save an R server script, configure an MCP client to launch it, and call
its tools.

## 1. Install mcplite

`mcplite` is not yet on CRAN. If needed, install `pak` first, then
install the development version from GitHub:

``` r

install.packages("pak")
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
and argument schema.

[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
blocks the R process while it serves requests. Put it at the end of a
client-launched script, after all tools have been defined or sourced.

## 3. Configure the client

Add a server entry to your MCP client’s configuration. Keep `Rscript` as
the command, and replace the server path below with the absolute path to
the `server.R` file you saved. The script path must be absolute because
the client’s working directory is not guaranteed.

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
server exits when standard input closes.

## Return ordinary R values

Ordinary R return values are the simplest default. Character values
become text, while other JSON-serializable values, such as the named
list returned by `inventory_status`, are encoded as JSON in a text
content block.

Use
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
only when a tool needs explicit MCP content blocks, structured content,
result metadata, or an error result. See the reference pages for
[`tool()`](https://tosidata.github.io/mcplite/reference/tool.md),
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md),
and the `content_*()` and `type_*()` helpers for the full API.

## Advanced next steps

- **Rich and structured results:**
  [`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
  supports explicit content and structured output. An `output_schema`
  advertises object-shaped structured content; when content is omitted,
  structured results include a text fallback for older clients.
- **Protocol compatibility:** `mcplite` negotiates its supported MCP
  version with the client. Some content types and structured output
  require newer MCP versions; the reference documentation records the
  compatibility details.
- **ellmer:** Compatible
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  definitions can be supplied directly to
  [`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
  when interoperability is needed.
- **OpenTelemetry:** Standard `otel` and `otelsdk` configuration
  applies. Never send telemetry to stdout: stdout is reserved for MCP
  protocol traffic. Use stderr or a remote exporter instead.

## Trust and safety

Schemas describe inputs and outputs to clients; they are not
authorization or sandboxing. Each tool function remains responsible for
domain validation, permission checks, credential handling, safe side
effects, and appropriate output and payload limits. Run the server with
only the operating-system and data permissions its tools need.
