# ADR 0003 — First format research slice: TIFF core before GeoTIFF/COG

## Status

Accepted as a research selection; not a production format commitment.

## Context

`imagery-d` needs multi-band, native-sample and window-capable raster input.
PNG is useful for a smoke test, but it does not exercise the geospatial
requirements that distinguish `imageio-d`. TIFF provides IFD metadata, strips,
tiles, planar configuration, multiple samples and reduced-resolution subfiles.
COG adds a defined layout and HTTP Range access on top of TIFF/GeoTIFF.

Implementing complete TIFF, GeoTIFF, BigTIFF, all compression codecs and COG
transport at once would make the first milestone unbounded.

## Decision

The first Pure-D research slice is a bounded TIFF core:

- little- and big-endian headers;
- IFD parsing with checked offsets and counts;
- dimensions, samples, bit depth, sample format and planar configuration;
- uncompressed strips and tiles;
- native `uint8`, `uint16` and `float32` sample preservation;
- caller-owned region output and explicit strides;
- technical metadata retention;
- malformed-input and resource-limit tests.

PNG remains an optional interoperability smoke case. GeoTIFF keys, BigTIFF,
compression codecs, overviews and HTTP Range/COG access are separate research
gates and are not implied by this selection.

## Rationale

This slice exercises the API properties that matter to `imagery-d` while
keeping the first parser and decoder auditable. TIFF tiles and overviews are
also structural foundations of COG.

## Exit criteria

- independent TIFF oracle and hashed fixtures;
- positive and negative parser corpus;
- exact samples for interleaved and planar cases;
- region equivalence against full decode;
- bounded allocations for metadata and tile payloads;
- DMD/LDC correctness and LDC performance results;
- explicit decision on compression, GeoTIFF and BigTIFF follow-up.
