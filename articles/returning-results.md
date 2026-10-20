# Return results

``` r

library(mcplite)
```

Start with ordinary R return values. Use
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
when a client needs structured data, rich content, result metadata, or
an explicit tool-level error. This guide builds on [Write
tools](https://tosidata.github.io/mcplite/articles/writing-tools.md);
the examples run without starting a server.

## Return an ordinary value

A tool can return a calculation, a string, or a named list directly:

``` r

inventory_value <- list(item = "coffee", count = 0L)
inventory_value
#> $item
#> [1] "coffee"
#> 
#> $count
#> [1] 0
```

For a tool return, character values become literal text; character
vectors are joined with newlines. Other JSON-serializable values, such
as this list, become JSON in a text content block. Bare lists are
ordinary values, not MCP result objects. Returning a JSON-looking string
does not opt into structured content.

See [Return-value
mappings](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact empty, missing, scalar, and array mappings. The distinction
matters if a client or output schema expects a particular JSON shape.

## Add structured data

Return `tool_result(structured_content = value)` when a client should
receive machine-readable data as well as text:

``` r

result <- tool_result(
  structured_content = list(item = "coffee", count = 0L),
  meta = list(source = "local inventory")
)
result$content[[1]]$text
#> [1] "{\"item\":\"coffee\",\"count\":0}"
```

When you omit `content`,
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
generates one JSON text fallback block. If you supply content
explicitly, it is kept without an extra fallback:

``` r

tool_result(
  content = content_text("Coffee is out of stock."),
  structured_content = list(item = "coffee", count = 0L)
)
```

Choose text that remains useful on its own: older protocols can omit
structured content or restrict its shape. The [compatibility
table](https://tosidata.github.io/mcplite/reference/mcp_server.html#protocol-compatibility)
shows what each supported version receives. JSON-looking strings,
including jsonlite `json` objects, remain string values in structured
content; they are not parsed or inserted as raw JSON.

## Include rich content

Build an ordered list of `content_*()` blocks. For example, return a
short summary with a self-contained text resource:

``` r

tool_result(content = list(
  content_text("Inventory snapshot attached."),
  content_resource(
    uri = "inventory:snapshot",
    text = "item,count\ncoffee,0\ntea,5\n",
    mime_type = "text/csv"
  )
))
```

The [content
constructors](https://tosidata.github.io/mcplite/reference/content-blocks.md)
also support images, audio, and resource links, with optional
annotations and metadata. Image, audio, and resource blob payloads must
already be base64-encoded: the constructors do not read files, download
URLs, infer MIME types, or encode the data. Tool authors own payload
integrity, access checks, and size limits.

A resource link carries your URI; it does not add a resource endpoint or
make the URI readable through the server. Audio, resource links, and
per-content metadata require MCP `2025-06-18` or later. A `2024-11-05`
call returning audio or a resource link receives a contained tool-level
error, not partial content.

For expected failures, set `is_error = TRUE` as shown in [Report
failures](https://tosidata.github.io/mcplite/articles/writing-tools.html#report-failures).

## Advertise structured output

Use `output_schema` on the tool to describe its structured result. This
example returns an array of strings:

``` r

search_items <- tool(
  function(query) {
    matches <- paste(query, c("alpha", "beta"), sep = "-")
    tool_result(structured_content = matches)
  },
  name = "search_items",
  description = "Find local items whose names start with a query.",
  arguments = list(query = type_string()),
  output_schema = type_array(type_string())
)
search_items("tea")$structured_content
#> [1] "tea-alpha" "tea-beta"
```

The schema is descriptive: `mcplite` checks container shape and
serializability, not full schema validity or result conformance. The
tool owns those guarantees. Modern MCP `2026-07-28` clients can receive
this array schema and structured value; legacy clients cannot. The tool
remains available and the generated text fallback still represents the
matches. See the [compatibility
table](https://tosidata.github.io/mcplite/reference/mcp_server.html#protocol-compatibility)
for object-shaped results and other versions.

## Choose payload encoding at startup

If default JSON mappings do not fit your payload, set package-global
options near the top of the server script, before constructing results
and calling
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md).
Keep them stable while the server runs. The [results
reference](https://tosidata.github.io/mcplite/reference/mcplite-results.html#payload-json-options)
lists the defaults, supported choices, and an executable example.

These options affect payload values, not protocol fields, schemas,
annotations, or result and content metadata. The tool still owns
output-schema conformance. For a per-tool text representation, return
your own JSON as ordinary character text, for example
`as.character(jsonlite::toJSON(value, na = "null"))`; it stays literal
text rather than becoming structured content.
