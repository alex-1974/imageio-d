# ADR 0007 — Shared transport for image and general data sources

## Status

Accepted as a workspace research direction; no transport package or public
API is admitted by this ADR.

## Context

`dunia` workflows need to download and load more than encoded images: OSM
data, image files, metadata documents and other resources share local,
remote, ranged and observable access requirements. An HTTP client hidden inside
`imageio-d` would duplicate that infrastructure and make image I/O responsible
for non-image data.

## Decision

Transport is a shared workspace capability used by applications and domain
libraries, including `imageio-d` and `dunia`. It provides source access; each
consumer remains responsible for interpreting the bytes.

```text
application / dunia
        |
        v
shared transport / access layer
    |       |       |
    v       v       v
 OSM     imageio   metadata/data sources
             |
             v
       image format decoder
```

The shared layer may support local files, memory, HTTP, bounded ranges,
timeouts, cancellation, retries, provenance, size limits and request metrics.
Those capabilities must be explicit and independently useful for OSM and image
workflows. A cache or scheduler requires its own contract.

`imageio-d` consumes a narrow source-access interface and owns encoded image
inspection/decoding. It must not own the HTTP client, general download policy,
OSM access, application cache or cross-resource scheduler.

`dunia` and the application choose transport policy and connect returned bytes
or ranges to the relevant decoder/parser. Generated imagery can bypass both
transport and image I/O.

## Next evidence

Build one transport-shaped consumer probe that uses the same source access for
an OSM byte resource and a Sentinel-2 COG window, records ranges/bytes/errors,
and passes the resulting bytes to independent OSM/image decoders. Keep the
transport probe outside imageio-d until the workspace package boundary is
decided.

The shared package now exists as `transport-d v0.1.0` on `develop`:
https://github.com/alex-1974/transport-d. `imageio-d` may use this released
contract in research-only consumer probes; adopting it does not admit a
public imageio-d API or make HTTP transport mandatory for every image source.
