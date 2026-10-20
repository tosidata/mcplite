# mcplite: Lightweight stdio MCP server for R

Expose R functions as tools for a local Model Context Protocol (MCP)
client. Define tools, save them in a script ending with
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md),
and configure the client to launch that script with `Rscript --vanilla`
and an absolute script path. The server blocks until standard input
closes.

## Define tools and return results

Use
[`mcplite::tool()`](https://tosidata.github.io/mcplite/reference/tool.md)
with the
[tool-types](https://tosidata.github.io/mcplite/reference/tool-types.md)
helpers to describe arguments. Tools remain directly callable R
functions. Return ordinary R values for text conversion, or
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
with
[`content_text()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
and other
[content-blocks](https://tosidata.github.io/mcplite/reference/content-blocks.md)
constructors for structured or rich output. See
[mcplite-results](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact return-value mappings and payload JSON options.

Schemas do not validate values or enforce permissions. Tools own domain
validation, authorization, safe side effects, and output limits. Keep
stdout exclusively for MCP protocol messages; use stderr for
diagnostics.

## Scope and next steps

`mcplite` is tools-only and stdio-only; embedded resources and resource
links in results do not provide resource endpoints. See
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
for server use, supported protocol versions, and optional tracing.
Compatible
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
objects are accepted, but ellmer is not required.

Website guides: [Get
started](https://tosidata.github.io/mcplite/articles/mcplite.html),
[Write
tools](https://tosidata.github.io/mcplite/articles/writing-tools.html),
and [Return
results](https://tosidata.github.io/mcplite/articles/returning-results.html).

## See also

Useful links:

- <https://tosidata.github.io/mcplite/>

- <https://github.com/tosidata/mcplite>

- Report bugs at <https://github.com/tosidata/mcplite/issues>

## Author

**Maintainer**: Juha Itkonen <juha@tosidata.com> \[copyright holder\]

Authors:

- Juha Itkonen <juha@tosidata.com> \[copyright holder\]
