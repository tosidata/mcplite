# Construct protocol-native MCP content blocks

These constructors create the only content-block objects accepted by
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md).
All R-facing names use `snake_case`; MCP names such as `mimeType` and
`_meta` are created only when a result is serialized.

## Usage

``` r
content_text(text, annotations = list(), meta = list())

content_image(data, mime_type, annotations = list(), meta = list())

content_audio(data, mime_type, annotations = list(), meta = list())

content_resource_link(
  uri,
  name,
  title = NULL,
  description = NULL,
  mime_type = NULL,
  size = NULL,
  annotations = list(),
  meta = list()
)

content_resource(
  uri,
  text = NULL,
  blob = NULL,
  mime_type = NULL,
  annotations = list(),
  meta = list()
)
```

## Arguments

- text:

  A single text string. For `content_resource()`, the resource text
  payload; exactly one of `text` or `blob` must be supplied.

- annotations:

  Optional named MCP annotations. Known R-facing fields are `audience`,
  `priority`, and `last_modified`; named extension fields are preserved
  when serializable.

- meta:

  Optional named outer content-block metadata. For `content_resource()`,
  metadata is not duplicated into the inner resource contents object.

- data:

  A scalar base64 string containing inline image or audio data.

- mime_type:

  A single MIME type string. Optional for resources and resource links.

- uri:

  A single non-empty author-supplied resource URI.

- name:

  A single non-empty resource-link name.

- title:

  Optional resource-link display title.

- description:

  Optional resource-link description.

- size:

  Optional non-negative whole-number resource size in bytes.

- blob:

  A scalar base64 string containing an embedded resource payload;
  exactly one of `text` or `blob` must be supplied.

## Value

A validated content block for use in
[`tool_result()`](https://tosidata.github.io/mcplite/reference/tool_result.md).

## Details

Image, audio, and resource blob data must already be scalar base64
strings. The constructors do not read files, download URLs, infer MIME
types, encode, decode, or validate base64 data, or invent resource URIs.
Tool authors own payload integrity, accurate MIME types, meaningful
URIs, authorization, sanitization, and payload size decisions.

Resource links only transport an author-supplied URI. `mcplite` remains
a tools-only server and does not make that URI readable or implement
`resources/read`. Embedded resources are self-contained content blocks.
