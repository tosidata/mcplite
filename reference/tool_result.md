# Construct protocol-native MCP tool results

`tool_result()` is the explicit opt-in boundary for returning
protocol-native MCP results. Its `content` must be created with one of
the `content_*()` constructors; ordinary R values, including bare lists
and JSON strings, retain the legacy single-text-block conversion used by
[`tool()`](https://tosidata.github.io/mcplite/reference/tool.md).

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

  Optional named list representing a JSON object. An empty object is
  allowed. `mcplite` does not validate this value against a tool's
  advertised output schema.

- is_error:

  Whether the result reports a tool error.

- meta:

  Optional named result metadata. MCP wire names such as `_meta` are
  created only during serialization.

## Value

A protocol-native tool result for return from a tool function.

## Details

When `structured_content` is supplied and `content` is omitted,
`tool_result()` generates exactly one JSON text fallback block.
Explicitly supplied content is preserved as-is and no fallback is
appended. Structured content and tool output schemas are sent only to
clients using MCP `2025-06-18` or later; older clients receive the
generated text fallback.

## See also

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
#> {"ok":true,"count":2} 
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
