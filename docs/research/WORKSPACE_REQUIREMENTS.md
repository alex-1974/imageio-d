# Decoder workspace requirements

This document defines the current measurable contract for caller-provided
temporary decode storage.

## Current PackBits paths

For an uncompressed representation of `bands` samples with `sampleBytes`
bytes per sample:

```text
rowBytes = width * bands * sampleBytes
```

The strip bridge requires, for each strip independently:

```text
scratch >= rowsInCurrentStrip * rowBytes
```

The tile bridge requires one full logical tile, including the padded edge:

```text
scratch >= tileWidth * tileHeight * bands * sampleBytes
```

The tile bridge deliberately uses the full tile dimensions rather than the
visible edge dimensions because TIFF tile payloads are padded to the logical
tile shape.

## Operational contract

- The caller owns and supplies the workspace.
- A decoder may overwrite the workspace during the call.
- A decoder must not retain the workspace after returning.
- Sequential operations may reuse one workspace.
- Concurrent operations require disjoint workspace regions.
- No decoder allocation is permitted on the hot path.
- The workspace size is a hard upper bound for decompression output; malformed
  or adversarial input must fail rather than grow an internal buffer.

## API gap

The experimental bridge status now distinguishes:

- `destinationTooSmall`: destination capacity too small; and
- `workspaceTooSmall`: decoder workspace capacity too small.

A size-query function or a typed workspace descriptor should still be
evaluated against the zero-allocation and `@nogc` requirements.

## Implemented boundary gate

`workspace_boundary_probe.d` now verifies under both DMD and LDC:

- an exactly sized strip workspace succeeds;
- a one-byte-short strip workspace fails;
- an exactly sized padded tile workspace succeeds;
- a one-byte-short padded tile workspace fails; and
- the visible edge pixels are copied correctly from the padded tile.

## Remaining research gates

1. Add boundary tests for exactly sufficient and one-byte-short workspaces.
2. Verify strip and tile requirements for 8-bit, 16-bit, multi-band and edge
   tile cases.
3. Define the corresponding bounds for Deflate and LZW before integrating
   those codecs.
4. Benchmark caller-provided workspace reuse against any typed wrapper.
