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

  Optional server instructions to advertise to clients using a protocol
  version that supports them.

## Value

`mcp_server()` is called for its side effect of serving MCP requests. It
blocks the current R process until standard input closes.

## Run a server

Supply one tool or a list of tools directly. Put the complete setup in a
script that defines or sources tools and ends with
`mcplite::mcp_server(actual_tool_or_list)`. Configure the MCP client to
launch it with `Rscript --vanilla /absolute/path/to/server.R`; use an
absolute script path because the client's working directory is not
guaranteed. The call blocks until standard input closes, so use a
client-launched script rather than an interactive R console.

Tools may return ordinary R values for text conversion or opt into
native content and structured output with
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md).
See
[mcplite-results](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact mappings and payload JSON options. Set those options before
constructing results and starting the server, and keep them stable while
it runs. Tools own input validation, output conformance, permissions,
and safe side effects; schemas are not authorization or sandboxing.

**Keep stdout exclusively for MCP protocol messages.** Send diagnostics
and telemetry to stderr or a remote exporter, not stdout.

## Server scope

`mcplite` is a tools-only, stdio-only server. It does not implement
JSON-RPC batching, HTTP transports, sessions, prompts, resource listing
or reading, subscriptions, cancellation, sampling, elicitation, roots,
Tasks, MCP Apps, progress notifications, or server-initiated and other
multi-round-trip requests. Embedded resource blocks are self-contained,
and resource links do not make their URIs readable through `mcplite`.

## Protocol compatibility

The same server definition supports four MCP versions. A tool remains
available when its output schema cannot be represented by the client's
protocol. Compatible explicit or generated text content remains
available when structured content is omitted. Tool authors still own
full schema validity and runtime input/output conformance.

|  |  |  |  |  |
|----|----|----|----|----|
| MCP version | Lifecycle | Output schemas | Structured content | Audio, resource links, per-content metadata |
| `2026-07-28` | Protocol selected per request | Every supported shape | Every supported JSON value | Supported |
| `2025-11-25` | `initialize` first | Direct object-root only | Object values only | Supported |
| `2025-06-18` | `initialize` first | Direct object-root only | Object values only | Supported |
| `2024-11-05` | `initialize` first | Omitted | Omitted | Unsupported |

Text, images, embedded resources, annotations, and result metadata work
in every supported version. A `2024-11-05` call returning audio or a
resource link receives a contained tool-level error instead of partial
content or server termination.

Modern `2026-07-28` clients select the protocol with per-request
metadata. `server/discover`, `tools/list`, and `tools/call` do not
require `initialize`. Discovery advertises `2026-07-28`, `2025-11-25`,
`2025-06-18`, and `2024-11-05` in that preference order. Every
successful modern result includes `resultType = "complete"` and the
server's canonical identity in
`_meta["io.modelcontextprotocol/serverInfo"]`. Modern `server/discover`
and `tools/list` results also include public cache hints with a 300000
millisecond TTL. Modern `ping` is unsupported. Legacy clients retain
`ping`, `tools/list`, and `tools/call` after initialization.

## OpenTelemetry tracing

`mcplite` automatically creates one OpenTelemetry server span for every
parsed MCP request or notification that passes JSON-RPC envelope
validation. This includes retained legacy initialization and ping,
notifications, modern discovery, tool listing and calls, and valid
unknown methods. Blank input, JSON parse failures, and malformed
JSON-RPC envelopes do not create MCP operation spans.

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
