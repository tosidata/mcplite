# Run an MCP server for R tools over stdio

`mcp_server()` runs a [Model Context
Protocol](https://modelcontextprotocol.io/) server over standard input
and output. It exposes tools created with
[`mcplite::tool()`](https://tosidata.github.io/mcplite/reference/tool.md)
so MCP clients can discover and call R functions. Compatible
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
objects can also be supplied when users already use ellmer, but ellmer
is not required for ordinary mcplite tools.

## Usage

``` r
mcp_server(tools, instructions = NULL)
```

## Arguments

- tools:

  Tool definitions to expose. Supply one
  [`mcplite::tool()`](https://tosidata.github.io/mcplite/reference/tool.md)
  object or a list of tool definitions. Compatible
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects are accepted when supplied directly.

- instructions:

  Optional server instructions to advertise to clients that negotiate a
  protocol version that supports them.

## Value

`mcp_server()` is called for its side effect of serving MCP requests. It
blocks the current R process until standard input closes.

## Details

`mcplite` supports the lifecycle, ping, `tools/list`, and `tools/call`
subset for protocol versions `2024-11-05`, `2025-06-18`, and
`2025-11-25`. Tools may return ordinary R values for legacy text
conversion or opt into native content and structured output with
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md).
Structured output, output schemas, audio, resource links, and
per-content metadata require MCP `2025-06-18` or later. Text, images,
embedded resources, annotations, and result metadata also work with
`2024-11-05`.

The server does not implement JSON-RPC batching, HTTP transports,
sessions, prompts, resource listing or reading, sampling, elicitation,
roots, tasks, progress notifications, or server-initiated requests.
Embedded resource blocks are self-contained, and resource links do not
make their URIs readable through `mcplite`.

Supply tool definitions directly. For client-launched workflows, put the
complete server setup in a script that defines or sources tools and ends
with `mcplite::mcp_server(actual_tool_or_list)`, then launch that script
with `Rscript --vanilla /absolute/path/to/server.R`.

## OpenTelemetry tracing

`mcplite` automatically creates one OpenTelemetry server span for every
parsed MCP request or notification that passes JSON-RPC envelope
validation. This includes initialization and notifications, ping, tool
discovery and calls, and valid unknown methods. Blank input, JSON parse
failures, and malformed JSON-RPC envelopes do not create MCP operation
spans.

Tool authors do not need to call
[`otel::start_local_active_span()`](https://otel.r-lib.org/reference/start_local_active_span.html)
for the MCP operation or tool invocation. The server span remains active
while tool code runs, so optional tool-authored spans can become
children without being required. `mcplite` does not create a redundant
automatic tool-execution child span.

Provider and exporter configuration belongs to the standard `otel` and
`otelsdk` environment variables and APIs. `mcplite` does not add
telemetry arguments, choose an exporter, or configure a provider. With
no exporter configured, tracing is an effective no-op and MCP behavior
is unchanged. A safe stderr configuration is
`OTEL_R_TRACES_EXPORTER=stderr Rscript --vanilla /absolute/path/to/server.R`;
a remote exporter such as OTLP is also suitable.

**Do not use a stdout or console exporter with a stdio MCP server.**
Standard output is reserved exclusively for MCP protocol messages, so
telemetry written there will corrupt the protocol stream.

Remote W3C parent context may be supplied in `params._meta.traceparent`,
with optional `params._meta.tracestate`. Malformed propagation data is
ignored, and `_meta` is not passed to tool functions. By default, spans
contain selected low-cardinality operation metadata; raw requests and
responses, tool arguments and results, `_meta`, trace headers, and
condition messages are not recorded as span attributes.

## Examples

``` r
if (identical(Sys.getenv("MCPLITE_CAN_BLOCK_PROCESS"), "true")) {
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
}
```
