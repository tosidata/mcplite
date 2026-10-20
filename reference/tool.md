# Define an MCP tool

`tool()` wraps an R function with MCP metadata. The resulting object can
be supplied directly, or in a list, to
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md).
Ordinary function return values use the default single-text-block
conversion; return
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
to opt into protocol-native content, structured output, or result
metadata.

## Usage

``` r
tool(
  fun,
  description,
  ...,
  arguments = list(),
  name = NULL,
  annotations = list(),
  output_schema = NULL
)
```

## Arguments

- fun:

  Function to expose as a tool.

- description:

  A single string describing when and how to use the tool.

- ...:

  Not used. Supply argument schemas with `arguments`.

- arguments:

  Named list of argument schemas created by the `type_*()` helpers, or
  one complete direct object-root schema created by
  [`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md).

- name:

  Optional tool name. If omitted, `tool()` uses the symbol name supplied
  to `fun`; anonymous functions must supply `name`. Tool names must use
  1 to 128 characters from letters, digits, underscore, dot, and hyphen.

- annotations:

  Optional named list of MCP tool annotations to advertise.

- output_schema:

  Optional output schema created by a supported `type_*()` helper. Raw
  schema lists must be wrapped with
  [`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md).
  See "Complete schemas and structured output" for author
  responsibilities and protocol compatibility.

## Value

The supplied function with MCP metadata attached. It remains directly
callable as an R function and can be supplied to
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md).

## Arguments and defaults

Incoming JSON arrays reach `fun` as R lists, not atomic vectors. Schemas
do not coerce or validate argument values or supply R defaults. Marking
a property `required = FALSE` permits omission in the advertised schema;
the R function must provide its own default for calls that omit that
argument.

## Return values

Ordinary character values become literal text, not parsed JSON. Bare
lists are ordinary values, not MCP result objects. See [Return-value
mappings](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
for exact conversions, empty and missing values, and payload JSON
options. Configure those options before constructing results and
starting the server.

## Complete schemas and structured output

`arguments` also accepts one complete object-root schema from
[`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md).
Complete input schemas must have direct root `type = "object"`; JSON
Schema 2020-12 keywords such as `$schema`, `$defs`, `$ref`, composition,
and conditionals are preserved.

An `output_schema` advertises the expected `structured_content` shape. A
client's protocol can omit an incompatible output schema without
removing the tool; see
[`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
under "Protocol compatibility" for the exact version rules. `mcplite`
checks schema container shape and serializability, not full schema
validity or runtime input/output conformance. Tool authors own those
guarantees.

## Examples

``` r
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
add_numbers(2, 3)
#> [1] 5
```
