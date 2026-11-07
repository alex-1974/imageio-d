# ADR 0006 — Image I/O for imagery, without duplicating adjacent libraries

## Status

Accepted as research/product direction. No production package, public API or
format support is admitted by this ADR.

## Context

The intended consumers are general image-editing software, scientific image
editing, and `dunia` for satellite-image analysis. Editors need both image
input and output; `dunia` needs input, while its first export workflow remains
to be specified. The current TIFF reader experiments prove only a narrow
part of the read/write product goal. `imagery-d` must also process generated
images without a file or an `imageio-d` dependency.

## Decision

`imageio-d` researches the Pure-D **read and write** boundary for encoded
images: format identification, technical inspection, bounded decode/encode,
native sample transfer, technical metadata and explicit capability, cost and
metadata-loss reporting. Common-format coverage is a product goal, not a
claim about the current research implementation. Each format and direction
(read/write) needs a declared subset and its own evidence gate.

Library ownership remains:

| Owner | Responsibility |
|---|---|
| `imageio-d` | Encoded format and codec mechanics; technical representation and metadata; transfer to/from caller-owned storage. |
| `raster-d` | Generic retained storage, views, strides, ROI, leases, ownership and raster execution. |
| `color-d` | Colour value types and colour mathematics. |
| `imagery-d` | Channel/product meaning, radiometry, alpha/NoData/validity policy, image processing and presentation intent. |
| Application/adapter | Select source, interpretation, processing and export policy; connect the libraries where needed. |

Codec-mandated representation transforms are part of format I/O. Optional
colour management, radiometric normalization, semantic band binding,
reprojection and display mapping are not implicit `imageio-d` operations.
`imageio-d` preserves or reports technical colour profiles, orientation,
georeferencing and other metadata as supported; it must not silently claim
that round-tripping through a format preserves unsupported metadata or native
samples. Export representation, lossy quality and metadata-loss policy are
explicit consumer choices.

Functional integration with `imagery-d` does not force a package dependency
from `imagery-d` to `imageio-d`. A thin application adapter may connect them;
generated imagery bypasses image I/O. No second raster buffer, colour engine,
image-semantic model, scheduler or cache framework belongs in `imageio-d`.

## Evidence before public admission

Use the three consumer flows in `docs/research/CONSUMER_READ_WRITE.md` to
review names, modules, ownership, failure states and capability reporting.
Actual consumer tests are currently unavailable; `dunia` is not yet ready.
In the meantime, standalone consumer-shaped probes and independent oracles
may advance research but must not be reported as real consumer validation.
Before public API admission, at least one actual read-to-processing-to-write
path must cross the real library boundaries. Lossless outputs need exact
sample and metadata checks; lossy outputs need an explicit tolerance and
independently decoded oracle.
No format is described as generally supported from one narrow fixture.

## Consequences

The bounded TIFF-first research decision in ADR 0003 remains valid as an
initial experiment, not a product-scope limit. JPEG read/write and PNG
read/write are distinct future format gates. Other common formats are selected
by a consumer-backed capability matrix rather than an unbounded promise.
