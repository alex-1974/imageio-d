# ADR 0004 — `@nogc` core and structured parser errors

## Status

Accepted as a research and API direction.

## Decision

The performance-critical Pure-D core should be `@nogc` wherever practical:

- header and metadata parsing;
- bounds validation;
- decompression into caller-owned buffers;
- sample conversion when no allocation is required;
- strip/tile traversal;
- region copying into caller-owned storage.

These paths must not require GC allocation for ordinary success or failure.
They should return a structured status/result carrying an error code and
technical context. Exceptions may be offered only as an explicit convenience
layer outside the `@nogc` core.

`@nogc` is not a claim that every operation is allocation-free. Owned-result
constructors, metadata materialization and convenience APIs may allocate when
their ownership contract requires it, but the allocation boundary must be
visible.

## Error model to research

Compare:

```d
Result!T read(...);
bool read(..., out T result, out Error error);
```

The selected form must support `@safe`, `@nogc`, useful diagnostics and no
partially initialized output after failure.

## Consequences

Positive:

- predictable latency and allocation behaviour;
- suitability for bounded-residency pipelines;
- easier integration with caller-owned `raster-d` storage;
- no hidden GC cost in parser hot paths.

Costs:

- more explicit error plumbing;
- owned convenience APIs need a separate allocation contract;
- exceptions cannot be the sole public failure mechanism.
