module overview_window_plan;

struct Level { uint width, height; double pixelSizeX, pixelSizeY; }
struct Area { uint x, y, width, height; }
struct Plan { bool found; uint level; Area sourceArea; }

Plan planWindow(scope const(Level)[] levels, Area requested,
    double requestedPixelSize) @safe pure nothrow @nogc
{
    if (!requested.width || !requested.height || requestedPixelSize <= 0)
        return Plan(false);
    uint chosen; bool found;
    foreach (i, level; levels)
        if (level.pixelSizeX <= requestedPixelSize
            && (!found || level.pixelSizeX > levels[chosen].pixelSizeX))
            { chosen = cast(uint)i; found = true; }
    if (!found) return Plan(false);
    const scale = levels[chosen].pixelSizeX / levels[0].pixelSizeX;
    const x = cast(uint)(requested.x / scale);
    const y = cast(uint)(requested.y / scale);
    const w = cast(uint)((requested.width + scale - 1) / scale);
    const h = cast(uint)((requested.height + scale - 1) / scale);
    if (x >= levels[chosen].width || y >= levels[chosen].height)
        return Plan(false);
    return Plan(true, chosen, Area(x, y,
        x + w > levels[chosen].width ? levels[chosen].width - x : w,
        y + h > levels[chosen].height ? levels[chosen].height - y : h));
}

version (OverviewWindowPlanProbe)
@safe @nogc nothrow
void main()
{
    const Level[3] levels = [Level(10980, 10980, 10, 10),
        Level(5490, 5490, 20, 20), Level(2745, 2745, 40, 40)];
    auto plan = planWindow(levels[], Area(100, 200, 32, 24), 25);
    assert(plan.found && plan.level == 1);
    assert(plan.sourceArea.x == 50 && plan.sourceArea.y == 100);
    assert(plan.sourceArea.width == 16 && plan.sourceArea.height == 12);
    assert(!planWindow(levels[], Area(1, 1, 0, 10), 25).found);
}
