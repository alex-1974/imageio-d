module overview_selection;

struct Overview
{
    uint width, height;
    double pixelSizeX, pixelSizeY;
}

struct Selection
{
    bool found;
    uint index;
}

Selection selectOverview(scope const(Overview)[] levels, double requestedX,
    double requestedY) @safe pure nothrow @nogc
{
    if (!levels.length || requestedX <= 0 || requestedY <= 0)
        return Selection(false, 0);
    Selection result;
    foreach (i, level; levels)
    {
        if (level.pixelSizeX <= requestedX && level.pixelSizeY <= requestedY)
        {
            if (!result.found || level.pixelSizeX > levels[result.index].pixelSizeX)
                result = Selection(true, cast(uint)i);
        }
    }
    return result;
}

version (OverviewProbe)
@safe @nogc nothrow
void main()
{
    const Overview[3] levels = [
        Overview(10980, 10980, 10, 10),
        Overview(5490, 5490, 20, 20),
        Overview(2745, 2745, 40, 40)
    ];
    assert(selectOverview(levels[], 10, 10).index == 0);
    assert(selectOverview(levels[], 25, 25).index == 1);
    assert(selectOverview(levels[], 80, 80).index == 2);
    assert(!selectOverview(levels[], 5, 5).found);
}
