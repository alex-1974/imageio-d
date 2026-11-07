# `imagery-d` consumer validation

## Current evidence

The isolated probe in `experiments/api_fit/source/imagery_consumer.d` models
the accepted `imagery-d` M2 rule that source revision and semantic production
bindings participate in materialization identity. It verifies:

- technical channels are not silently assigned product meaning;
- changing a semantic binding changes the materialization key;
- changing the source revision invalidates reuse;
- generated/non-file sources can use the same downstream plan shape.

The vocabulary follows `imagery-d`'s accepted Source/Resource/Revision and
materialization/cache boundary documents. No imageio-d type owns an imagery
cache, scheduler, NoData policy or radiometric conversion.

The sibling repository's real M2 source/cache/pipeline contract experiment was
also executed from its repository boundary on 2026-10-26. Both DMD and LDC
passed semantic production-key identity, single-flight, cancellation,
`RasterLease` lifetime after cache eviction, covering ROI and equal-output
execution strategies. This validates the consumer architecture and lifetime
vocabulary, but it does not yet compile imageio-d decoder code into that
experiment because imageio-d remains research-only.

## Deferred imageio-d consumer smoke test

Real imageio-d consumer tests are not currently possible, and `dunia` is not
yet ready. When an integration consumer becomes available, place the test at
the repository boundary where the real `imagery-d` types are available. It
must materialize one native 8-/16-bit TIFF result and assert:

1. technical channel count and sample width survive;
2. explicit semantic bindings are preserved;
3. source revision/provenance survives;
4. NoData, mask and alpha remain distinct;
5. a generated source bypasses imageio-d;
6. retained result lifetime outlives reader/cache disposal.

Until that test exists, the crosswalk remains research evidence rather than a
public integration contract.

## Broader read/write consumer evidence

This imagery-d handoff is necessary but no longer sufficient for the product
scope. ADR 0006 and `CONSUMER_READ_WRITE.md` add general image-editing,
scientific image-editing and `dunia` satellite-analysis flows. At least one
real read -> imagery processing -> write path must be exercised without
moving raster storage, colour mathematics or image semantics into imageio-d.
No such end-to-end write consumer has been demonstrated yet. Until real
consumers are ready, standalone consumer-shaped sketches and independent
format oracles may proceed, but they do not close this admission gate.

