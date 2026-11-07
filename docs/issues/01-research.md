## Goal
Determine whether a D-native image-I/O library with a D-idiomatic API provides
enough independent value to justify implementation, and identify its smallest
useful first format/consumer slice.

## Inputs
Use README, ROADMAP and RESEARCH in this repository; read the canonical
workspace engineering rules and imagery-d M1/M2 ADRs before API decisions.

## Deliverables
- [ ] Pinned reference matrix: Gamut, imageformats, OpenImageIO, GDAL, libvips.
- [ ] Native sample/channel/metadata fidelity matrix.
- [ ] Real PNG, 16-bit TIFF, COG/windowed and generated-data consumer cases.
- [ ] Read/write consumer cases for general and scientific image editing,
      plus an actual `dunia` satellite product workflow.
- [ ] Separate JPEG, PNG and TIFF read/write capability and metadata-loss
      matrix; do not infer format support from the first TIFF reader probe.
- [ ] Ownership/strides/ROI/zero-copy evidence with raster-d.
- [ ] Error/safety, dependency/licence and memory/performance evidence.
- [ ] Decision: standalone package vs optional adapter/binding; no API admission by assumption.

## Required product evidence

- [ ] At least one concrete consumer and preferably two independent consumer
      flows.
- [ ] API comparison showing why the D-native API is clearer than direct use
      of Gamut, imageformats or native bindings.
- [ ] Native sample, metadata, NoData and mask fidelity evidence.
- [ ] Pure-D DMD/LDC correctness and optimized-performance evidence.
- [ ] Explicit ownership/lifetime and bounded-memory contract.
- [ ] Independent oracle and reproducible corpus with hashes.
- [ ] Written trade-off decision for every candidate first format.
