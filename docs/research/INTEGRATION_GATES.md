# Integration gates

## Local unit gate

```sh
./check.sh
```

Runs DMD and LDC imageio tests against the local transport and compression
dependencies.

## Public GeoTIFF gate

```sh
experiments/public_tiff_consumer/check.sh
```

Requires GDAL to generate the reproducible tiled/overview fixtures. It tests
the public imageio API rather than internal TIFF research modules.

## Imagery gate

```sh
cd /home/alexander/Dokumente/ChatGPT/imagery-d
./check-io.sh
experiments/imageio_consumer/check.sh
```

This verifies both the default imageio-enabled configuration and the
`no-io` configuration.

The public fixture gate is intentionally separate from the minimal CI job;
CI runners without GDAL must not silently skip or pretend to execute it.
