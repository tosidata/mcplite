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

  Named list of argument schemas created by the `type_*()` helpers.

- name:

  Optional tool name. If omitted, `tool()` uses the symbol name supplied
  to `fun`; anonymous functions must supply `name`. Tool names must use
  1 to 128 characters from letters, digits, underscore, dot, and hyphen.

- annotations:

  Optional named list of MCP tool annotations to advertise.

- output_schema:

  Optional object-shaped output schema created by a supported `type_*()`
  helper. Raw schema lists must be wrapped with
  [`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md).
  The schema is advertised to MCP `2025-06-18` and later clients; tool
  authors remain responsible for result conformance.

## Value

A lightweight mcplite tool definition.

## Details

Character values are returned as literal text, character vectors are
joined with newlines, and other JSON-serializable R values are encoded
as JSON. Pre-serialized JSON strings remain text, and bare lists are
ordinary values, not MCP result objects.

An `output_schema` advertises the expected object-shaped
`structured_content` to MCP `2025-06-18` and later clients. `mcplite`
checks that the normalized schema has JSON-object wire shape and is
serializable, but does not perform runtime schema validation.

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
```
