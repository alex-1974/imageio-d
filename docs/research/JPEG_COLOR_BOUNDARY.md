# JPEG component and colour boundary (research decision)

Status: research direction, **not** an accepted public API or format gate.

JPEG entropy coding, quantization, DCT/IDCT, sampling factors and component
planes are image-I/O responsibilities. A baseline JPEG frame identifies
components and sampling geometry; it does not, by itself, make every
three-component codestream RGB or YCbCr. JFIF, Adobe APP14, ICC and other
metadata can constrain interpretation. The reader must inspect and report
what is actually signalled, and refuse or leave uninterpreted ambiguous cases.
The [JFIF specification](https://www.ijg.org/files/T-REC-T.871-201105-I%21%21PDF-E.pdf)
specifically requires YCbCr for its three-component interchange form.

Generic RGB↔YCbCr mathematics, ICC transforms, gamma, rendering intent and
semantic colour-space conversion belong to `color-d` or an application-level
adapter, not to the core `imageio-d` format parser. `raster-d` owns plane
storage/views; `imagery-d` owns image meaning. A JPEG reader may expose
codec-native component planes with their native subsampling, quantization and
metadata; an RGB view must be an *explicit* request with a visible conversion
and resampling policy. Likewise, an RGB editor save path must explicitly
select a conversion to JPEG components and must not smuggle colour conversion
into an apparently lossless `write` call.

The current `experiments/jpeg_gate/source/jpeg_research.d` is an internal
oracle/throughput surrogate. Its older `encodeJpeg`/`decodeJpeg` RGB8 signatures
remain for oracle compatibility, but `encodeJfifPlanes` and `decodeJpegPlanes`
now exercise caller-owned native Y/Cb/Cr planes (or gray) without colour
conversion or chroma resampling. `inspectJpegFrame` reports raw component IDs,
sampling factors and JFIF/Adobe/unknown signalling. The RGB convenience read
rejects unmarked and Adobe-raw-RGB three-component streams rather than guessing
YCbCr; native-plane read leaves those components uninterpreted. The new plane
probe checks 17×19 odd dimensions in 4:4:4/4:2:2/4:2:0, padded strides,
canaries, missing JFIF and contradictory Adobe APP14. Pillow and ImageMagick reopen every
encoded variant and DMD/LDC output bytes match on this small fixture. These
experimental names and signatures are **not** a model for an admitted public
API. The Q16 integer transform in the legacy RGB experiment is a
compiler-reproducibility probe, not a proposal to duplicate `color-d` in a
production image-I/O library. Its numerical coefficients and colour error
must be reviewed with `color-d` if an explicit adapter is later built.

Before admission, test at least:

- broader JFIF, Adobe APP14 raw-RGB/YCbCr and unmarked three-component files,
  including ICC conflicts and independent oracle content beyond synthetic data;
- native-plane output and subsampling geometry across more layouts and limits;
- explicit opt-in conversion through the accepted `color-d` interface,
  including clear ownership of chroma upsampling and edge policy;
- DMD/LDC reproducibility, quality against independent decoders, ICC/EXIF
  reporting, and failure on ambiguous interpretations;
- real editor/scientific consumer snippets for read-process-write and
  metadata-loss reporting.

Until those checks exist, do not describe `decodeJpeg`'s RGB8 result as
"native JPEG output" or promote its current names and defaults.
