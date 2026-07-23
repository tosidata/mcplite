# mcplite 0.1.0

* First release of the lightweight, tools-only Model Context Protocol (MCP)
  server over standard input and output (stdio), supporting the MCP lifecycle,
  ping, `tools/list`, and `tools/call`.
* Supports protocol versions `2024-11-05`, `2025-06-18`, and `2025-11-25`.
* Provides native tool and JSON Schema helpers, with optional interoperability
  for compatible `ellmer` tool definitions.
* Adds explicit protocol-native tool results through `tool_result()` and the
  `content_text()`, `content_image()`, `content_audio()`,
  `content_resource_link()`, and `content_resource()` constructors. Results may
  contain ordered mixed content, structured content, annotations, and metadata
  while ordinary R return values retain their existing text conversion.
* Adds object-shaped `output_schema` support to `tool()`. Tool definitions and
  results follow the negotiated MCP version: structured output, output schemas,
  audio, resource links, and content metadata are available for `2025-06-18`
  and later, with compatible fallback or contained tool errors for
  `2024-11-05`.
* Handles protocol negotiation, request validation, JSON-RPC errors, and MCP
  tool-call errors while keeping the stdio protocol stream usable.
* Automatically traces every envelope-valid MCP operation with one
  OpenTelemetry server span, while keeping tool-authored child spans optional.
  Standard `otel` and `otelsdk` configuration owns provider and exporter
  selection, remote W3C parent context is accepted through `params._meta`, and
  request or tool content is not captured by default. Stdio servers must use a
  stderr or remote exporter because stdout is reserved for MCP messages; with
  no exporter configured, tracing is an effective no-op.
