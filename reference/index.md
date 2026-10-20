# Package index

## Connect a client

Package orientation and server setup.

- [`mcplite`](https://tosidata.github.io/mcplite/reference/mcplite.md)
  [`mcplite-package`](https://tosidata.github.io/mcplite/reference/mcplite.md)
  : mcplite: Lightweight stdio MCP server for R
- [`mcp_server()`](https://tosidata.github.io/mcplite/reference/mcp_server.md)
  : Run an MCP server for R tools over stdio

## Write tools

Describe functions and their input and output schemas.

- [`tool()`](https://tosidata.github.io/mcplite/reference/tool.md) :
  Define an MCP tool
- [`type_boolean()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_integer()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_number()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_string()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_enum()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_array()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_object()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_from_schema()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  [`type_ignore()`](https://tosidata.github.io/mcplite/reference/tool-types.md)
  : Define MCP tool schemas

## Return results

Construct results and look up exact serialization rules.

- [`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md)
  : Construct protocol-native MCP tool results
- [`content_text()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  [`content_image()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  [`content_audio()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  [`content_resource_link()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  [`content_resource()`](https://tosidata.github.io/mcplite/reference/content-blocks.md)
  : Construct protocol-native MCP content blocks
- [`mcplite-results`](https://tosidata.github.io/mcplite/reference/mcplite-results.md)
  : Return-value mappings and payload JSON options
