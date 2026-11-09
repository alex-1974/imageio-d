# Changelog

This file records release changes and post-release validation commitments.

## 0.1.1 — bounded public release

- added the format-neutral bounded TIFF writer entry points `writeImage` and
  `writeImageFile`;
- added same-directory atomic file publication and explicit writer request,
  sink, limit and failure contracts;
- exposed TIFF decode cost/path reporting for bounded COG-style reads;
- documented public Sentinel-2/COG window decoding, overview selection and
  the remaining remote-consumer boundaries;
- refreshed generated DDox coverage for the new writer and decoder contracts.

## 0.1.0 — release candidate

- qualified TIFF read/write scope for classic TIFF and BigTIFF UInt8/UInt16
  chunky strips/tiles, uncompressed, Deflate, PackBits, LZW and baseline
  JPEG-in-TIFF paths;
- qualified non-interlaced PNG and baseline JPEG read/write paths with explicit
  representation, metadata-loss and resource-limit policies;
- added caller-owned source/destination, explicit sinks, partial-write
  results, malformed-input handling and DMD/LDC consumer gates;
- added clean package-archive, licence, dependency and rendered DDox checks;
- documented unsupported variants and post-release real-consumer,
  second-host, fuzzing and broader performance validation.

## Historical research baseline

- merged the neutral `ImageRegion`/`ImagePlane` geometry and metadata probes;
- qualified DMD/LDC TIFF, GeoTIFF consumer and research-gate CI runs;
- aligned the transport integration with `transport-d` v0.2.1 and its
  structured `ReadResult` failure contract;
- clarified package metadata and Ddoc module boundaries;
- retained explicit unsupported-variant and technical-metadata boundaries;
  no claim of a complete TIFF/JPEG/PNG implementation is made.

The declared 0.1.0 subset, ownership/lifetime contract, generated Ddoc site,
dependency revisions, compatibility policy and consumer smoke tests are frozen
together. Real application integration is tracked after publication.
