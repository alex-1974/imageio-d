# API-fit experiment

Research-only compile probe for the provisional D-native vocabulary. This is
not a package, public module tree or production implementation.

Run `./run.sh`. The probe models technical metadata and explicit native reads
without implementing a codec or allocating pixels. It also checks one valid
borrowed return and one invalid lifetime escape under DIP1000.

The destination probe checks explicit caller-owned bytes, row/pixel/band
strides, selected bands, native-sample intent, NoData and scale/offset without
assigning those technical facts an imagery or colour meaning.

The metadata probe checks that four technical channels do not automatically
become RGBA and that semantic roles are attached only by an explicit consumer
binding.

`api_fit.d` now uses the selected consumer-facing vocabulary:
`ImageSource`, `ImageReader`, `ImageInfo`, `ReadArea`, `ReadOptions` and
`ReadResult`. Codec terms are intentionally absent from that call surface.

`destination_layout.d` exercises the corresponding caller-owned path with
`ImageBuffer` and `readInto(area, options, buffer, metadata)`. Strides remain
visible because they describe the caller's storage; the buffer is not an
imageio-d-owned raster type.

`write_fit.d` covers the matching export vocabulary: `ImageWriter`,
`ImageTarget`, `WriteOptions` and `WriteResult`. It requires an explicit value
form and metadata-loss choice and reports completion and bytes written. It is a
naming/contract probe only, not an encoder.

`error_contract.d` fixes the research distinction between a failed read,
complete write and partial write. It also requires metadata loss to be
reported and explicitly allowed; silent loss is not part of the vocabulary.
