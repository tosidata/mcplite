# Return-value mappings and payload JSON options

Tools can return ordinary R values for text conversion, or
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
for explicit MCP content and structured data. This topic defines the
shared serialization contract. See
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
for construction and fallback, and
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
under "Protocol compatibility" for version projection.

## Ordinary return values

Character scalars become literal text and character vectors are joined
with newlines. Other JSON-serializable values become JSON in one text
content block. Bare lists are ordinary values, not MCP result objects.
Ordinary `NULL` becomes the text `"{}"`; an ordinary unnamed
[`list()`](https://rdrr.io/r/base/list.html) becomes `"[]"`.

For per-tool conversion choices, return your own JSON as ordinary
character text, for example
`as.character(jsonlite::toJSON(value, na = "null"))`. JSON-looking
strings and jsonlite `json` objects are never parsed or inserted as raw
JSON. In `structured_content`, they remain string values.

## Structured-content mappings

Structured values follow
[`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
and the payload options below, with one root convention: a bare empty
list at the structured root represents
[`{}`](https://rdrr.io/r/base/Paren.html). Nested unnamed empty lists
retain jsonlite's `[]` mapping. `NULL` means absence of the
structured-content field, not a JSON null value.

With default options:

|  |  |
|----|----|
| R value | Structured-content meaning |
| `list(ok = TRUE)` | JSON object |
| `c("a", "b")` | JSON array |
| `"done"` | JSON string scalar, not parsed as JSON |
| [`list()`](https://rdrr.io/r/base/list.html) or `structure(list(), names = character())` | Empty object [`{}`](https://rdrr.io/r/base/Paren.html) |
| `I(list())` | Explicit empty array `[]` |
| `NA` or `NA_character_` | JSON `null` |
| `NA_integer_`, `NA_real_`, or `NA_complex_` | JSON string `"NA"` |
| `NULL` | No structured-content field |

Classes, dimensions, and explicit
[`I()`](https://rdrr.io/r/base/AsIs.html) or
[`jsonlite::unbox()`](https://jeroen.r-universe.dev/jsonlite/reference/unbox.html)
representations retain their jsonlite mappings. Tool authors are
responsible for conformance with any advertised output schema.

## Payload JSON options

Configure these package-global R options before constructing results and
starting the server, and keep them stable while the server runs:

- `mcplite.json.null`: `"null"` (default) or `"list"`. Named payload
  `NULL` fields remain present, as JSON `null` or
  [`{}`](https://rdrr.io/r/base/Paren.html), respectively.

- `mcplite.json.na`: unset by default, which omits jsonlite's `na`
  argument and preserves its class-specific defaults. Set `"null"` or
  `"string"` to select that jsonlite mapping. `"null"` also maps `NaN`
  and infinities to JSON `null` and retains missing data-frame fields
  instead of omitting them.

- `mcplite.json.auto_unbox`: `TRUE` (default) or `FALSE`. Setting
  `FALSE` keeps singleton payload vectors as arrays; explicit
  [`I()`](https://rdrr.io/r/base/AsIs.html) and
  [`jsonlite::unbox()`](https://jeroen.r-universe.dev/jsonlite/reference/unbox.html)
  representations still apply.

Remove an option with `NULL`, for example
`options(mcplite.json.na = NULL)`, to restore its default. This omits
`na`; it does not forward `na = NULL`. These options apply to ordinary
noncharacter return-value JSON and to structured content, its
representability checks, generated text fallback, and protocol-version
projection. Protocol fields, schemas, annotations, and all result and
content metadata retain fixed encoding.

## See also

[mcplite](https://tosidata.github.io/mcplite/reference/mcplite.md),
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md),
[`content_text()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)

## Examples

``` r
local({
  old <- options(mcplite.json.na = "null", mcplite.json.auto_unbox = FALSE)
  on.exit(options(old))
  result <- tool_result(structured_content = list(
    count = 1L,
    values = c(NA_real_, NaN, Inf, -Inf),
    rows = data.frame(id = 1L, missing = NA_real_)
  ))
  result$content[[1]]$text
})
#> [1] "{\"count\":[1],\"values\":[null,null,null,null],\"rows\":[{\"id\":1,\"missing\":null}]}"
```
