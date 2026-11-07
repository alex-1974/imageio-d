module imagery_consumer;

enum Role { red, green, blue, validity }
struct Revision { ulong value; }
struct Binding { uint technicalBand; Role role; }

struct MaterializationPlan
{
    Revision revision;
    uint width;
    uint height;
    uint bitsPerSample;
    bool nativeSamples;
    Binding[4] bindings;
}

ulong productionIdentity(scope const(MaterializationPlan) plan)
    @safe pure nothrow @nogc
{
    ulong result = plan.revision.value;
    result = result * 131 + plan.width;
    result = result * 131 + plan.height;
    result = result * 131 + plan.bitsPerSample;
    result = result * 131 + plan.nativeSamples;
    foreach (binding; plan.bindings)
    {
        result = result * 131 + binding.technicalBand;
        result = result * 131 + binding.role;
    }
    return result;
}

@safe @nogc nothrow
void main()
{
    MaterializationPlan plan = MaterializationPlan(
        Revision(42), 16, 8, 16, true,
        [Binding(0, Role.red), Binding(1, Role.green),
         Binding(2, Role.blue), Binding(3, Role.validity)]
    );
    auto first = productionIdentity(plan);
    plan.bindings[0] = Binding(3, Role.red);
    assert(productionIdentity(plan) != first);
    plan.bindings[0] = Binding(0, Role.red);
    plan.revision = Revision(43);
    assert(productionIdentity(plan) != first);
}
