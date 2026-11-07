# ADR 0001 — Pure-D native direction

## Status

Accepted as research direction; production implementation remains gated.

## Context

The project must provide a reason for consumers to choose `imageio-d` over
Gamut, imageformats, GDAL, OpenImageIO or libvips. A wrapper around an existing
native backend would add another abstraction without establishing that reason.
`imagery-d` and `raster-d` also require explicit D ownership, lifetime,
strides, regions and leases.

## Decision

The target `imageio-d` implementation is Pure D from the beginning. Existing
libraries are reference implementations and comparison baselines, not runtime
backends or wrapper dependencies.

The first admitted implementation must be deliberately narrow and must prove:

- format correctness against an independent oracle;
- native sample and technical-metadata fidelity;
- explicit malformed-input and resource-limit behaviour;
- DMD correctness and LDC optimized performance;
- ownership/lifetime compatibility with `raster-d`;
- a concrete consumer benefit over direct use of an existing library.

This decision does not require implementing every format in Pure D. It requires
choosing the first format based on consumer evidence and maintaining a clear
path for later independent format modules.

## Consequences

Positive:

- no C/C++ ABI or native runtime is required by the core;
- D ownership, slices, `scope`, `@safe` and `@nogc` can be designed directly;
- the API can match `raster-d` and `imagery-d` without translation types;
- deployment and cross-compilation can be simpler.

Costs and risks:

- codec implementation and security maintenance become project-owned;
- broad format coverage cannot be assumed;
- performance must be demonstrated rather than inherited from mature native
  implementations;
- format specifications, test corpora and malformed-input testing are part of
  the research burden.

## Rejected for now

- native backend wrappers as the target architecture;
- a universal codec suite before a concrete consumer slice;
- treating Pure D alone as evidence of product value.
