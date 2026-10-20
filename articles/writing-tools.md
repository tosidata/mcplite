# Write tools

``` r

library(mcplite)
```

Use [`tool()`](https://tosidata.github.io/mcplite/reference/tool.md) to
make an R function discoverable and callable by an MCP client. If you
have not connected a client yet, follow [Get
started](https://tosidata.github.io/mcplite/articles/mcplite.md) first.
The examples here can be called directly in R without starting a server.

## Describe arguments and defaults

Give each tool a name and a description that tells the client when to
use it. Use a named list of `type_*()` helpers to describe the
arguments. Marking an argument `required = FALSE` permits the client to
omit it; the R function must still provide its own default.

Incoming JSON arrays reach the function as R lists, not atomic vectors.
Convert them when the R operation needs a vector. This tool uses
[`unlist()`](https://rdrr.io/r/base/unlist.html) before summing and
defaults to a multiplier of 1:

``` r

sum_numbers <- tool(
  function(values, multiplier = 1) {
    sum(unlist(values, use.names = FALSE)) * multiplier
  },
  name = "sum_numbers",
  description = "Sum numeric values and apply an optional multiplier.",
  arguments = list(
    values = type_array(type_number("A value to include.")),
    multiplier = type_number("Scale the sum.", required = FALSE)
  )
)
sum_numbers(list(2, 3))
#> [1] 5
sum_numbers(list(2, 3), multiplier = 2)
#> [1] 10
```

The returned tool remains an R function, so direct calls are useful for
checking its calculations. They do not exercise MCP serialization or
client behavior. Pass the tool to `mcp_server(list(sum_numbers))` in
your server script when it is ready.

Schemas describe arguments; they do not coerce or validate values. Add
the domain checks your function needs, rather than relying on a client
to obey the schema. See [tool
schemas](https://tosidata.github.io/mcplite/reference/tool-types.md) for
the helpers and
[`tool()`](https://tosidata.github.io/mcplite/reference/tool.md) for
naming rules and optional tool annotations.

## Report failures

An error raised by a tool, such as `stop("Unknown item")`, is contained
and returned to the MCP client as a tool-level error. A direct R call
still raises the ordinary R error.

For an expected domain failure, you can instead return an explicit
result:

``` r

out_of_stock <- tool_result(
  content = content_text("The requested item is out of stock."),
  is_error = TRUE
)
```

Use `is_error = TRUE` to distinguish failure from a successful text
response. See [Return
results](https://tosidata.github.io/mcplite/articles/returning-results.md)
for other result choices, and [Return-value
mappings](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact conversion rules and payload options.

## Keep access and side effects explicit

Each tool owns domain validation, authorization, credential handling,
safe side effects, output sanitization, and any needed rate or payload
limits. Schemas are not a security boundary. In particular,
[`type_ignore()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
only omits an argument from the advertised schema; it does not reject a
caller-supplied argument or enforce permissions.

Keep stdout exclusively for MCP protocol traffic when the tool runs in
the server. Send diagnostics to stderr, not
[`print()`](https://rdrr.io/r/base/print.html) or
[`cat()`](https://rdrr.io/r/base/cat.html) on stdout.

## Describe a complete input schema

Use
[`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
when property helpers are not enough. A complete input schema must have
direct root `type = "object"`. JSON Schema 2020-12 keywords such as
`$schema`, `$defs`, `$ref`, composition, and conditionals are preserved.
When `$schema` is absent, MCP treats the schema as JSON Schema 2020-12.

``` r

find_items <- tool(
  function(query) {
    paste(query, c("alpha", "beta"), sep = "-")
  },
  name = "find_items",
  description = "Find local items whose names start with a query.",
  arguments = type_from_schema(list(
    type = "object",
    properties = list(
      query = list(type = "string", minLength = 1)
    ),
    required = list("query"),
    additionalProperties = FALSE
  ))
)
find_items("tea")
#> [1] "tea-alpha" "tea-beta"
```

`mcplite` checks schema container shape and serializability, not full
schema validity or runtime input/output conformance. The tool above
advertises a nonempty query but does not enforce that constraint. Tool
functions own those guarantees.

An `output_schema` describes structured results rather than ordinary
text returns. See [Advertise structured
output](https://tosidata.github.io/mcplite/articles/returning-results.html#advertise-structured-output)
for an example and the compatibility qualification.

## Reuse ellmer tools

Compatible
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definitions can be supplied directly to
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md).
`ellmer` is optional; tools created with
[`mcplite::tool()`](https://tosidata.github.io/mcplite/reference/tool.md)
do not require it. See
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
for server setup and supported scope.
