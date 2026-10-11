## Goal
Compare existing image I/O implementations and decide whether an independent
`imageio-d` production package is justified.

## Inputs
Use README, ROADMAP and RESEARCH in this repository; read the canonical
workspace engineering rules and imagery-d M1/M2 ADRs before API decisions.

## Deliverables
- [ ] Pinned reference matrix: Gamut, imageformats, OpenImageIO, GDAL, libvips.
- [ ] Native sample/channel/metadata fidelity matrix.
- [ ] Real PNG, 16-bit TIFF, COG/windowed and generated-data consumer cases.
- [ ] Ownership/strides/ROI/zero-copy evidence with raster-d.
- [ ] Error/safety, dependency/licence and memory/performance evidence.
- [ ] Decision: standalone package vs optional adapter/binding; no API admission by assumption.
