# ADR 0002 — D-idiomatic API as a product requirement

## Status

Accepted as research direction; names and public types are not yet admitted.

## Context

The library must feel like a natural D library. Its value depends on reducing
integration code and making ownership, technical representation and region
behaviour obvious. API names and module boundaries therefore affect product
fit, not just style.

## Decision

API research must begin with consumer flows and competing snippets, not with
codec internals. The provisional vocabulary is:

```text
source → reader → inspect/info → read request → owned or borrowed result
```

For the product read/write requirement, a separate encoder/write flow must
also be compared with real consumers. The reader vocabulary above is not a
complete proposed `imageio-d` API; ADR 0006 records ownership boundaries.

The design must investigate distinct concepts for:

- encoded source and opened reader;
- technical `ImageInfo`/metadata;
- region/window and band selection;
- native versus explicitly converted representation;
- caller-owned output versus owned result;
- structured read errors and capabilities.
- explicit writer/encoder selection, technical input representation, output
  ownership, format options, partial-write semantics and metadata-loss report.

The API must use D-idiomatic structs, slices, properties, `ref`, `scope` and
attributes where they improve the contract. Core parse/decode paths should be
`@nogc` and use structured result errors. It must reuse `raster-d` terms for
storage, view, ROI, stride, plane, lease and ownership instead of inventing a
parallel raster vocabulary.

The common API must not infer RGBA, colour space, radiometry, alpha/NoData
equivalence or semantic band meaning. Those decisions belong to `imagery-d` or
the consumer.

## Research questions

- Which five consumer flows make the API feel natural in D?
- What is the smallest stable object model: source, reader, info, request,
  result and error?
- Can ownership and borrowing be made visible in types without duplicating
  `raster-d` storage abstractions?
- How are backend/format capabilities reported without leaking codec details?
- Which module layout gives the best import and documentation experience?
- How should `@safe`, DIP1000, `@nogc`, `nothrow` and `scope` be applied?
- Which write flow is D-idiomatic without hiding conversion, lossy output,
  allocation or partial files?

## Consequences

API ergonomics, naming and module structure must be tested before production
implementation. A technically correct decoder with an awkward or ambiguous
API does not satisfy this ADR.
