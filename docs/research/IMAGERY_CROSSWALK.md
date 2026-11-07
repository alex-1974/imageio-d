# Technical-to-imagery crosswalk

This is a research contract between the Pure-D TIFF slice and `imagery-d`.
`imageio-d` reports the left-hand side only. The right-hand side requires an
explicit consumer/product binding.

| `imageio-d` technical fact | `imagery-d` interpretation | Rule |
|---|---|---|
| `SamplesPerPixel = 4` | four unnamed/technical components | never infer RGBA |
| channel name `B04` | sensor/product band meaning | explicit binding required |
| `SampleFormat = unsigned integer` | stored digital number | no automatic reflectance conversion |
| `BitsPerSample = 16` | native 16-bit storage | no implicit normalization to `[0,1]` |
| TIFF `NoData` tag | technical missing-value marker | not alpha and not validity semantics by itself |
| TIFF mask/subfile | technical mask source | consumer chooses validity relationship |
| `PhotometricInterpretation = RGB` | technical RGB declaration | colour-space/presentation contract remains explicit |
| TIFF scale/offset | technical value transform metadata | radiometric meaning requires product metadata |
| GeoTIFF CRS key | geospatial reference candidate | CRS binding belongs above image I/O |
| overview/subimage | alternate technical resolution | imagery policy selects level and resampling |

## Required consumer evidence

- [ ] one `imagery-d` consumer binds technical channels explicitly;
- [ ] NoData, mask and alpha remain distinguishable;
- [ ] native samples survive materialization;
- [ ] source revision/provenance survives the handoff;
- [ ] semantic binding changes the production key where required;
- [ ] generated/non-file imagery can bypass `imageio-d`.
