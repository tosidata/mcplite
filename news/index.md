# Changelog

## mcplite 0.2.0

- Adds stateless MCP `2026-07-28` support while retaining
  initialize-based MCP `2024-11-05`, `2025-06-18`, and `2025-11-25`.
  Modern discovery, tool listing, and tool calls work without
  initialization; legacy ping behavior is preserved, while modern ping
  is unsupported.
- Adds `server/discover` with deterministic four-version ordering.
  Successful modern results include canonical server identity and
  `resultType = "complete"`; discovery and tool-list results include
  public cache hints.
- Expands tool schemas and protocol-native results. Complete object-root
  input schemas retain JSON Schema 2020-12 keywords; modern clients can
  receive supported output-schema roots and all JSON structured-content
  shapes, while older protocols receive compatible projections and
  fallback content.
- Adds payload options `mcplite.json.null`, `mcplite.json.na`, and
  `mcplite.json.auto_unbox`, preserving published defaults and fixed
  protocol and metadata encoding. See
  [`help("mcplite-results")`](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
  for configuration details.
- Restores empty structured-root lists as
  [`{}`](https://rdrr.io/r/base/Paren.html) and removes the unreleased
  scalar-NA coercion in favor of jsonlite’s class-specific mappings.

## mcplite 0.1.0

CRAN release: 2026-08-03

- First release of the lightweight, tools-only Model Context Protocol
  (MCP) server over standard input and output (stdio), supporting the
  MCP lifecycle, ping, `tools/list`, and `tools/call`.
- Supports protocol versions `2024-11-05`, `2025-06-18`, and
  `2025-11-25`.
- Provides native tool and JSON Schema helpers, with optional
  interoperability for compatible `ellmer` tool definitions.
- Adds explicit protocol-native tool results through
  [`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
  and the
  [`content_text()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
  [`content_image()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
  [`content_audio()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
  [`content_resource_link()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
  and
  [`content_resource()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  constructors. Results may contain ordered mixed content, structured
  content, annotations, and metadata while ordinary R return values
  retain their existing text conversion.
- Adds object-shaped `output_schema` support to
  [`tool()`](https://tosidata.github.io/mcplite/reference/tool.md). Tool
  definitions and results follow the negotiated MCP version: structured
  output, output schemas, audio, resource links, and content metadata
  are available for `2025-06-18` and later, with compatible fallback or
  contained tool errors for `2024-11-05`.
- Handles protocol negotiation, request validation, JSON-RPC errors, and
  MCP tool-call errors while keeping the stdio protocol stream usable.
- Automatically traces every envelope-valid MCP operation with one
  OpenTelemetry server span, while keeping tool-authored child spans
  optional. Standard `otel` and `otelsdk` configuration owns provider
  and exporter selection, remote W3C parent context is accepted through
  `params._meta`, and request or tool content is not captured by
  default. Stdio servers must use a stderr or remote exporter because
  stdout is reserved for MCP messages; with no exporter configured,
  tracing is an effective no-op.
