# Construct protocol-native MCP tool results

`tool_result()` is the explicit opt-in boundary for returning
protocol-native MCP results. Its `content` must be created with one of
the `content_*()` constructors; ordinary R values, including bare lists
and JSON strings, retain the single-text-block conversion used by
[`mcplite::tool()`](https://tosidata.github.io/mcplite/reference/tool.md).

## Usage

``` r
tool_result(
  content = list(),
  structured_content = NULL,
  is_error = FALSE,
  meta = list()
)
```

## Arguments

- content:

  One content block created by a `content_*()` constructor, or an
  ordered list of such blocks. Omitting `content` permits automatic text
  fallback generation from `structured_content`; explicit
  `content = list()` suppresses fallback and is invalid.

- structured_content:

  Optional R value representable as a JSON object, array, or scalar.
  `NULL` means absence; a bare empty list at this root represents
  [`{}`](https://rdrr.io/r/base/Paren.html). See
  [mcplite-results](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
  for other mappings and payload options. `mcplite` checks JSON
  representability but does not validate this value against a tool's
  advertised output schema.

- is_error:

  Whether the result reports a tool error.

- meta:

  Optional named result metadata. MCP wire names such as `_meta` are
  created only during serialization.

## Value

A protocol-native tool result for return from a tool function.

## Content and fallback

When `structured_content` is supplied and `content` is omitted,
`tool_result()` generates exactly one JSON text fallback block.
Explicitly supplied content is preserved as-is and no fallback is
appended. Keep that content useful on its own: a client's protocol may
omit structured content or restrict its shape. See
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
under "Protocol compatibility".

See [Return-value
mappings](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact R-to-JSON mappings and payload options. JSON-looking strings
and jsonlite `json` objects remain string values in
`structured_content`; they are not parsed as raw JSON. Tool authors own
conformance with any advertised output schema.

## Tool errors

`is_error = TRUE` reports a tool-level error while retaining the normal
MCP tool-result envelope.

## See also

[mcplite-results](https://tosidata.github.io/mcplite/reference/mcplite-results.md),
[`content_text()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
[`content_image()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
[`content_audio()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
[`content_resource_link()`](https://tosidata.github.io/mcplite/reference/content-blocks.md),
and
[`content_resource()`](https://tosidata.github.io/mcplite/reference/content-blocks.md).

## Examples

``` r
tool_result(content_text("Done."))
#> $content
#> $content[[1]]
#> $type
#> [1] "text"
#> 
#> $text
#> [1] "Done."
#> 
#> $annotations
#> named list()
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_content_text" "mcplite_content"     
#> 
#> 
#> $structured_content
#> NULL
#> 
#> $is_error
#> [1] FALSE
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_tool_result"

tool_result(
  content = list(
    content_text("Generated the plot."),
    content_image("base64-data", "image/png")
  )
)
#> $content
#> $content[[1]]
#> $type
#> [1] "text"
#> 
#> $text
#> [1] "Generated the plot."
#> 
#> $annotations
#> named list()
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_content_text" "mcplite_content"     
#> 
#> $content[[2]]
#> $type
#> [1] "image"
#> 
#> $data
#> [1] "base64-data"
#> 
#> $mime_type
#> [1] "image/png"
#> 
#> $annotations
#> named list()
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_content_image" "mcplite_content"      
#> 
#> 
#> $structured_content
#> NULL
#> 
#> $is_error
#> [1] FALSE
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_tool_result"

tool_result(structured_content = list(ok = TRUE, count = 2L))
#> $content
#> $content[[1]]
#> $type
#> [1] "text"
#> 
#> $text
#> [1] "{\"ok\":true,\"count\":2}"
#> 
#> $annotations
#> named list()
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_content_text" "mcplite_content"     
#> 
#> 
#> $structured_content
#> $structured_content$ok
#> [1] TRUE
#> 
#> $structured_content$count
#> [1] 2
#> 
#> 
#> $is_error
#> [1] FALSE
#> 
#> $meta
#> named list()
#> 
#> attr(,"class")
#> [1] "mcplite_tool_result"
```
