# Define MCP tool argument schemas

These helpers create the JSON Schema subset that `mcplite` advertises
for tool arguments. They describe inputs for clients; tool functions
still own domain validation, coercion, authorization or access checks,
side-effect safety, output sanitization, and rate limiting where needed.

## Usage

``` r
type_boolean(description = NULL, required = TRUE)

type_integer(description = NULL, required = TRUE)

type_number(description = NULL, required = TRUE)

type_string(description = NULL, required = TRUE)

type_enum(values, description = NULL, required = TRUE)

type_array(items, description = NULL, required = TRUE)

type_object(
  .description = NULL,
  ...,
  .required = TRUE,
  .additional_properties = FALSE
)

type_from_schema(text = NULL, path = NULL)

type_ignore()
```

## Arguments

- description:

  Optional argument description.

- required:

  Whether the argument is listed as required in the parent schema.

- values:

  Allowed enum values.

- items:

  Type helper describing each array item.

- .description:

  Optional object description.

- ...:

  Named properties for object schemas.

- .required:

  Whether the object itself is listed as required in its parent schema.

- .additional_properties:

  Whether to allow additional properties.

- text:

  A JSON Schema as a list or JSON string.

- path:

  Path to a JSON Schema file. Exactly one of `text` or `path` must be
  supplied.

## Value

A lightweight mcplite tool type object.

## Details

Generated schemas are MCP-compatible JSON Schema objects. When `$schema`
is absent, MCP treats schemas as JSON Schema 2020-12.
`type_from_schema()` callers are responsible for supplying valid
MCP-compatible schemas. List input preserves the supplied R list shape:
use a named empty list for [`{}`](https://rdrr.io/r/base/Paren.html) and
an unnamed empty list for `[]`.

## Examples

``` r
type_string("A label.")
#> $kind
#> [1] "string"
#> 
#> $description
#> [1] "A label."
#> 
#> $required
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_string" "mcplite_tool_type"       

type_array(type_integer(), description = "Integer values.")
#> $kind
#> [1] "array"
#> 
#> $description
#> [1] "Integer values."
#> 
#> $required
#> [1] TRUE
#> 
#> $items
#> $kind
#> [1] "integer"
#> 
#> $description
#> NULL
#> 
#> $required
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_integer" "mcplite_tool_type"        
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_array" "mcplite_tool_type"      

type_object(
  .description = "A labeled score.",
  label = type_string(),
  score = type_number(required = FALSE)
)
#> $kind
#> [1] "object"
#> 
#> $description
#> [1] "A labeled score."
#> 
#> $required
#> [1] TRUE
#> 
#> $properties
#> $properties$label
#> $kind
#> [1] "string"
#> 
#> $description
#> NULL
#> 
#> $required
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_string" "mcplite_tool_type"       
#> 
#> $properties$score
#> $kind
#> [1] "number"
#> 
#> $description
#> NULL
#> 
#> $required
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_number" "mcplite_tool_type"       
#> 
#> 
#> $additional_properties
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_object" "mcplite_tool_type"       

type_from_schema(list(
  type = "string",
  minLength = 1
))
#> $kind
#> [1] "schema"
#> 
#> $description
#> NULL
#> 
#> $required
#> [1] TRUE
#> 
#> $schema
#> $schema$type
#> [1] "string"
#> 
#> $schema$minLength
#> [1] 1
#> 
#> 
#> attr(,"class")
#> [1] "mcplite_tool_type_schema" "mcplite_tool_type"       
```
