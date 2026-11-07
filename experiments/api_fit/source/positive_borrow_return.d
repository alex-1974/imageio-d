module positive_borrow_return;

struct BorrowedRegion
{
    int[] data;
}

@safe
BorrowedRegion validReturn(return scope int[] borrowed)
{
    return BorrowedRegion(borrowed);
}

@safe
void main()
{
    int[4] storage;
    auto result = validReturn(storage[]);
    result.data[0] = 1;
}
