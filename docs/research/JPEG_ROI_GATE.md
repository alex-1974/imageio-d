# JPEG ROI decoder gate

This is a separate research gate from the native JPEG plane contract.

## Current implementation

`decodeJpegRegion` validates a reference-grid window, decodes complete native
component planes, and crops each plane with its declared spacing. The result
preserves source model, component roles, sampling geometry, plane origins and
row strides. For non-aligned crops, `ImagePlane.referenceOffsetX/Y` records the
exact fractional crop-boundary alignment in reference-grid units; it is not a
chroma-siting claim and does not turn unknown source phase into known geometry.
Full-decode fallback is observable in the API documentation and
is not presented as cheap native ROI access.

## Required admission evidence for native MCU ROI

- exact 4:2:0 and 4:2:2 ROI corpus, including odd dimensions and MCU edges;
- independent decoder comparison for every returned native sample;
- malformed/truncated input and output-limit negatives;
- proof of plane-origin and phase behaviour for every supported siting state;
- measured encoded bytes read, decoded bytes, peak residency and copy count;
- DMD/LDC correctness and optimized measurements;
- consumer evidence that partial MCU decoding materially improves the workflow.

Until this evidence exists, the fallback is the qualified behaviour and native
MCU skipping remains research-only.
