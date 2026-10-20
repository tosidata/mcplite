# Vendored MCP specification references

These files are copied from `modelcontextprotocol/modelcontextprotocol` for
local compatibility checks while implementing `mcplite`.

- Upstream repository: https://github.com/modelcontextprotocol/modelcontextprotocol
- Final `2026-07-28` tag and pinned commit:
  `5f5440bb26a62e2cf3440b92da5a667efa03b267`
- Legacy-reference commit: `f04ab539afc1810747b8b2ead6a1849e15702f2e`
- Upstream license copied to `docs/mcp-spec/LICENSE`
- Included protocol versions: `2024-11-05`, `2025-03-26`, `2025-06-18`,
  `2025-11-25`, `2026-07-28`

This directory intentionally keeps only references relevant to `mcplite`'s
package goals: a lightweight stdio MCP server for R tools.

## Kept references

- `schema/*.json`: canonical JSON schemas for every stable protocol version
  used as implementation or compatibility evidence.
- `docs/messages.mdx`, `versioning.mdx`, `transports.mdx`, `discover.mdx`,
  `tools.mdx`, and `caching.mdx`: final `2026-07-28` prose for the bounded
  stdio tools surface.
- The remaining `docs/*.mdx` files retain focused `2025-11-25` lifecycle
  evidence for the supported legacy path.
- `changelog/*.mdx`: upstream changelogs for version-to-version compatibility
  differences where upstream provides them.

## Deliberately omitted

- `schema.ts`: TypeScript SDK-oriented definitions; redundant for this R
  package because `schema.json` is the canonical machine-readable contract.
- Per-version copies of the same prose docs: the schemas and changelogs cover
  version differences with less duplication.
- Draft specification files: `mcplite` should track stable protocol versions
  unless support for draft features is added deliberately.

## Upstream path mapping

- `schema/2024-11-05.json` ← `schema/2024-11-05/schema.json`
- `schema/2025-03-26.json` ← `schema/2025-03-26/schema.json`
- `schema/2025-06-18.json` ← `schema/2025-06-18/schema.json`
- `schema/2025-11-25.json` ← `schema/2025-11-25/schema.json`
- `schema/2026-07-28.json` ← `schema/2026-07-28/schema.json`
- `docs/messages.mdx` ← `docs/specification/2026-07-28/basic/index.mdx`
- `docs/versioning.mdx` ← `docs/specification/2026-07-28/basic/versioning.mdx`
- `docs/transports.mdx` ← `docs/specification/2026-07-28/basic/transports/stdio.mdx`
- `docs/discover.mdx` ← `docs/specification/2026-07-28/server/discover.mdx`
- `docs/tools.mdx` ← `docs/specification/2026-07-28/server/tools.mdx`
- `docs/caching.mdx` ← `docs/specification/2026-07-28/server/utilities/caching.mdx`
- `docs/lifecycle.mdx` ← `docs/specification/2025-11-25/basic/lifecycle.mdx`
- `docs/ping.mdx` ← `docs/specification/2025-11-25/basic/utilities/ping.mdx`
- `docs/server-capabilities.mdx` ← `docs/specification/2025-11-25/server/index.mdx`
- `docs/pagination.mdx` ← `docs/specification/2025-11-25/server/utilities/pagination.mdx`
- `changelog/2025-03-26.mdx` ← `docs/specification/2025-03-26/changelog.mdx`
- `changelog/2025-06-18.mdx` ← `docs/specification/2025-06-18/changelog.mdx`
- `changelog/2025-11-25.mdx` ← `docs/specification/2025-11-25/changelog.mdx`
- `changelog/2026-07-28.mdx` ← `docs/specification/2026-07-28/changelog.mdx`
