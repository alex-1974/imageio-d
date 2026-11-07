module negative_borrow_escape;

@safe
int[] invalidEscape(scope int[] borrowed)
{
    // This must not compile with DIP1000: the returned slice may outlive the
    // caller-owned buffer passed to the reader.
    return borrowed;
}

void main() {}
