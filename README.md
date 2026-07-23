# mcplite

<!-- badges: start -->
[![R-CMD-check](https://github.com/tosidata/mcplite/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tosidata/mcplite/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`mcplite` lets you expose R functions as [Model Context Protocol](https://modelcontextprotocol.io/)
(MCP) tools. It runs a small server over standard input and output, which is the
transport most desktop MCP clients use to launch local tool servers.

Use it when you want an MCP client to call R code such as data lookups,
calculations, report helpers, or local automation.

## Installation

After its CRAN release, install `mcplite` with:

```r
install.packages("mcplite")
```

For development from a local source checkout, install from the repository root
with your usual R package workflow. For example:

```r
pak::pkg_install(".")
```

`mcplite` includes lightweight tool definition helpers, so `ellmer` is not
required for ordinary tool servers.

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

Configure your MCP client to launch that script with `Rscript`. Use an absolute
path so the client can find it regardless of its working directory. A Claude
Desktop-style configuration looks like this:

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

After restarting the client, it should discover `add_numbers` and make it
available for tool calls. `mcp_server()` starts serving immediately and keeps
running until its standard input closes, so it is normally launched by the MCP
client rather than run interactively at the R console.

A server script may source helper files, but its final call to `mcp_server()`
must receive a tool object or a list of tool objects.

## Return rich and structured results

By default, character results become text and other JSON-serializable R values
are returned as JSON in one text block. Bare lists are ordinary return values,
not MCP result objects.

Use `tool_result()` when a tool needs explicit protocol-native content. Its
content must come from `content_text()`, `content_image()`, `content_audio()`,
`content_resource_link()`, or `content_resource()`; raw MCP-shaped lists are not
accepted.

```r
plot_tool <- tool(
  function() {
    encoded_png <- "already-base64-encoded-image-data"

    tool_result(
      content = list(
        content_text("Generated the requested plot."),
        content_image(encoded_png, "image/png")
      ),
      meta = list(trace_id = "plot-1")
    )
  },
  name = "plot",
  description = "Generate a plot."
)
```

Structured tools can advertise an object-shaped output schema and return a JSON
object as `structured_content`:

```r
weather <- tool(
  function(city) {
    tool_result(
      structured_content = list(
        city = city,
        temperature = 22.5,
        conditions = "Partly cloudy"
      )
    )
  },
  name = "weather",
  description = "Get structured weather data.",
  arguments = list(city = type_string("City name.")),
  output_schema = type_object(
    city = type_string(),
    temperature = type_number(),
    conditions = type_string()
  )
)
```

When `content` is omitted, structured results include a serialized JSON text
fallback for compatibility with older clients. `mcplite` validates the object
shape of structured content and output schemas, but tool authors remain
responsible for semantic conformance between them.

Protocol-dependent result behavior is:

| Feature | `2024-11-05` | `2025-06-18` / `2025-11-25` |
|---|---|---|
| Text, inline image, embedded resource | Supported | Supported |
| Audio, resource link | Entire explicit result is rejected as a tool error | Supported |
| `structuredContent`, `outputSchema` | Omitted; structured-only results use text fallback | Supported |
| Result `_meta` | Supported | Supported |
| Content `_meta` | Omitted | Supported |
| Content annotations | Supported | Supported |

## Server instructions

You can pass optional instructions that describe when or how clients should use
your R tools:

```r
mcplite::mcp_server(
  list(add_numbers),
  instructions = "Use these tools for small calculations and local R helpers."
)
```

## Compatibility and scope

`mcplite` supports MCP protocol versions `2024-11-05`, `2025-06-18`, and
`2025-11-25` for the lifecycle, ping, and `tools/list` / `tools/call` methods.
Unsupported client protocol versions negotiate to the latest supported version.

The server intentionally implements only the stdio tools portion of MCP. It does
not provide HTTP transports, JSON-RPC batching, sessions, prompts, resource
listing or reading, sampling, elicitation, roots, tasks, progress notifications,
or server-initiated requests. Embedded resources may still be returned as
self-contained tool content.

## Optional ellmer interoperability

Existing users can pass compatible `ellmer::tool()` definitions directly to
`mcp_server()`. Common text and inline-image results are adapted; unsupported or
provider-specific content becomes an actionable tool error rather than being
downloaded or converted speculatively. The native `mcplite::tool()`, `type_*()`,
and `content_*()` helpers remain the recommended API for new servers.

## OpenTelemetry tracing

`mcplite` automatically creates an OpenTelemetry server span for each valid MCP
operation. The span remains active while a tool runs, so spans created by tool
code can become its children without any required tool-side instrumentation.
Tracing uses the standard `otel` and `otelsdk` configuration and is effectively
a no-op when no exporter is configured.

For example, after installing `otelsdk`, send traces to standard error with:

```sh
OTEL_SERVICE_NAME=r-tools \
OTEL_R_TRACES_EXPORTER=stderr \
Rscript --vanilla /absolute/path/to/server.R
```

A remote exporter such as OTLP is also suitable. **Never use a stdout or console
exporter with a stdio MCP server:** standard output is reserved for MCP protocol
messages, and telemetry written there will corrupt the stream.

Remote W3C parent context may be supplied through `params._meta.traceparent`
and `params._meta.tracestate`. By default, spans contain selected
low-cardinality operation metadata rather than raw requests, tool arguments,
results, or trace headers.

## Operational behavior

- Argument schemas describe inputs for clients; tool functions remain
  responsible for domain validation, authorization, side-effect safety, output
  sanitization, and rate limiting.
- Tool conditions, invalid results, unsupported result types, and serialization
  failures are returned as concise MCP tool errors rather than terminating the
  server.
- Standard output is reserved for MCP JSON messages. Output printed by tools is
  captured so it cannot corrupt the protocol stream.

## Function reference

See `?tool` for tool definitions, `?type_object` for the schema helpers,
`?tool_result` and `?content_text` for protocol-native results, and
`?mcp_server` for server behavior, protocol scope, ellmer interoperability, and
OpenTelemetry details.
