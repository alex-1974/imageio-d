## Goal

Design and evaluate a D-native API that feels like a natural extension of D,
`raster-d` and `imagery-d`.

## Consumer flows

These are target flows, not available real-consumer tests. `dunia` is not yet
ready. Standalone sketches/probes may proceed; the real-consumer review and
end-to-end integration remain open for later public admission.

- [ ] Open a file and inspect metadata without decoding pixels.
- [ ] Read a complete PNG into an owned result.
- [ ] Read a native multi-band TIFF region into caller-owned storage.
- [ ] Read from encoded memory bytes and a caller-supplied stream.
- [ ] Select bands, layout, destination and explicit conversion.
- [ ] Transfer technical metadata and provenance into an `imagery-d` plan.
- [ ] Handle malformed input, unsupported capability and cancellation.
- [ ] Keep a result alive after reader disposal and cache eviction.
- [ ] General editor: read JPEG/PNG technical data, process through imagery,
      then save an explicitly selected format/representation.
- [ ] Scientific editor: preserve native high-depth/multiband samples and
      technical metadata across a lossless read/write path.
- [ ] `dunia`: exercise a real satellite product through imageio -> raster ->
      imagery with explicit semantic binding; establish actual export need.
- [ ] Make encoder options, destination ownership, partial writes, lossy
      quality and metadata-loss policy visible in the API.

## Deliverables

- [ ] Review `docs/research/API_SKETCHES.md` with at least one real consumer.
- [x] Add an isolated positive DMD/LDC compile probe for the provisional
      source/reader/info/request/result vocabulary.
- [x] Add positive and negative borrowed-lifetime probes under DIP1000.
- [x] Add a caller-owned destination probe for bands, strides and technical
      metadata.
- [x] Add a technical-versus-semantic metadata boundary probe.
- [x] Document the technical-to-`imagery-d` metadata crosswalk.
- [x] Add an isolated consumer materialization-key probe.
- [x] Record the provisional reader/request/result API shape in ADR 0005.
- [ ] At least three competing API sketches for the flows above.
- [ ] Import/module layout comparison.
- [ ] Naming and vocabulary crosswalk with `raster-d` and `imagery-d`.
- [ ] Ownership/lifetime compile probes under DMD and LDC.
- [ ] DDoc examples for the selected design.
- [ ] Decision recorded in ADR before production types are created.
- [x] Record the read/write ownership direction in ADR 0006; public names and
      per-format capabilities remain unadmitted.
- [x] Add a compile-only caller-owned PNG read/write boundary probe under
      DMD/LDC; it is not real raster/imagery/application integration.
- [ ] Compare the two read/write shapes in
      `docs/research/READ_WRITE_API_BOUNDARY.md` against actual raster-d views
      and available consumers before selecting public names.

## Non-goals

- [ ] Do not implement a public universal reader while the API is still being
      compared.
- [ ] Do not add image-semantic interpretation to make examples shorter.
