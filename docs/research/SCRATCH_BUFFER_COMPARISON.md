# Scratch workspace comparison: imageio-d and containers-d

## Finding

`containers-d` does provide a dedicated `ScratchBuffer(T)` abstraction in
its package source. It is a reusable, contiguous, typed buffer with one
owned runtime allocation and a resettable live prefix. Related types are:

- `ScratchBuffer(T)`: reusable contiguous storage;
- `StaticRingBuffer(T, Capacity)` stores a fixed-capacity FIFO inline.
- `RingBuffer(T)` owns one runtime-sized backing allocation and exposes FIFO
  operations and borrowed slices.
- `RuntimeStorageOwner` is an internal owning byte-storage primitive.

`ScratchBuffer(ubyte)` is therefore a valid comparison candidate, but it owns
storage and models a live prefix, while imageio receives a caller-owned
borrowed byte slice.

## Comparison

| Aspect | imageio-d decode scratch | `ScratchBuffer(ubyte)` | `StaticRingBuffer` | `RingBuffer` |
|---|---|---|---|
| Ownership | Caller-owned, borrowed | Container-owned allocation | Inline in container | Container-owned allocation |
| Lifetime | One decode operation | Reusable container lifetime | Container lifetime | Container lifetime |
| Semantics | Raw temporary byte workspace | Reusable contiguous storage | FIFO queue | FIFO queue |
| Allocation during decode | None | None after reserve | None if capacity fits | Storage owned by container |
| API shape | `scope ubyte[]` | Live prefix and reset | Push/pop/ring operations | Push/pop/ring operations |
| Concurrency | One workspace per concurrent operation | External synchronization | External synchronization | External synchronization |
| Suitable for decompression | Yes | Adaptable, but owning | No | No |

## Decision

Compressed image decoders should continue to accept caller-owned
`scope ubyte[] scratch` (or the equivalent workspace parameter in a future
API). This keeps the hot path allocation-free and makes ownership, lifetime,
and concurrency explicit. A consumer may use `containers.ScratchBuffer!ubyte`
and pass its live slice to imageio, but imageio should not require
`containers-d` for the decoder contract.

The scratch contents are operation-local and must not be retained by a
decoder after the call returns. A caller that performs concurrent decodes
provides separate workspace regions.

## Follow-up research

Before stabilising the public API, measure and specify:

1. the minimum workspace size for each compression and tile/strip path;
2. whether a single workspace can be reused sequentially across formats;
3. whether the API should expose a workspace-size query or a typed workspace
   wrapper around `scope ubyte[]`;
4. whether a future shared low-level workspace package is justified.

For now, making `containers-d` a dependency would add ownership and package
coupling without improving the decoder contract.
