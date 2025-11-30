# Custom Redbean Binary

Place the **Purpose-Built Redbean** binary (compiled with `SQLITE_ENABLE_FTS5`) in this directory.

Filename: `redbean.com`

## Why?
This custom build enables **Smart Context** (FTS5 + BM25) functionality in Connect.
If this file is missing, the build scripts will fall back to downloading the standard `redbean.com` from `redbean.dev`, which uses a compatibility shim (slower, no ranking).
