# Changelog

This file records research and release-preparation changes. No supported
version has been published yet.

## Unreleased research baseline

- merged the neutral `ImageRegion`/`ImagePlane` geometry and metadata probes;
- qualified DMD/LDC TIFF, GeoTIFF consumer and research-gate CI runs;
- aligned the transport integration with `transport-d` v0.2.1 and its
  structured `ReadResult` failure contract;
- clarified package metadata and Ddoc module boundaries;
- retained the explicit research-only status: no stable public API, complete
  TIFF claim or DUB release is admitted.

Before a versioned release, the supported format subset, ownership/lifetime
contract, generated Ddoc site, dependency revisions, compatibility policy and
consumer smoke test must be frozen and reviewed together.
