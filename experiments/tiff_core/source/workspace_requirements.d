module workspace_requirements;

enum WorkspaceStatus { ok, invalidGeometry, overflow }

struct WorkspaceResult
{
    WorkspaceStatus status;
    size_t bytes;
    @property bool ok() const @safe pure nothrow @nogc
    { return status == WorkspaceStatus.ok; }
}

private WorkspaceResult product(size_t a, size_t b)
    @safe pure nothrow @nogc
{
    if (a != 0 && b > size_t.max / a)
        return WorkspaceResult(WorkspaceStatus.overflow, 0);
    return WorkspaceResult(WorkspaceStatus.ok, a * b);
}

WorkspaceResult stripBytes(uint width, uint rows, uint bands, uint sampleBytes)
    @safe pure nothrow @nogc
{
    if (width == 0 || rows == 0 || bands == 0 || sampleBytes == 0)
        return WorkspaceResult(WorkspaceStatus.invalidGeometry, 0);
    auto result = product(width, rows);
    if (!result.ok) return result;
    result = product(result.bytes, bands);
    if (!result.ok) return result;
    return product(result.bytes, sampleBytes);
}

WorkspaceResult tileBytes(uint tileWidth, uint tileHeight, uint bands, uint sampleBytes)
    @safe pure nothrow @nogc
{
    return stripBytes(tileWidth, tileHeight, bands, sampleBytes);
}

version (WorkspaceRequirementProbe)
@safe @nogc nothrow
void main()
{
    assert(stripBytes(3, 2, 1, 1).bytes == 6);
    assert(tileBytes(4, 4, 2, 2).bytes == 64);
    assert(stripBytes(0, 1, 1, 1).status == WorkspaceStatus.invalidGeometry);
    assert(stripBytes(uint.max, uint.max, uint.max, uint.max).status == WorkspaceStatus.overflow);
}
