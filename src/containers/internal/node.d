module containers.internal.node;

template fatNodeCapacity(size_t bytesPerItem, size_t pointerCount,
	T, size_t cacheLineSize = 64)
{
	enum size_t optimistic = (cacheLineSize
		- ((void*).sizeof * pointerCount) - T.sizeof) / bytesPerItem;
	static if (optimistic > 0)
		enum fatNodeCapacity = optimistic;
	else
		enum fatNodeCapacity = 1;
}

// Double linked fat node of int with bookkeeping in a uint should be able to
// hold 11 ints per node.
// 64 - 16 - 4 = 4 * 11
version (X86_64)
	static assert (fatNodeCapacity!(int.sizeof, 2, uint) == 11);

template shouldNullSlot(T)
{
	import std.traits;
	enum shouldNullSlot = isPointer!T || is (T == class);
}

template shouldAddGCRange(T)
{
	import std.traits;
	enum shouldAddGCRange = isPointer!T || hasIndirections!T || is (T == class);
}

static assert (shouldAddGCRange!string);
static assert (!shouldAddGCRange!int);

template fullBits(size_t n, size_t c = 0)
{
	static if (c >= (n - 1))
		enum fullBits = (1 << c);
	else
		enum fullBits = (1 << c) | fullBits!(n, c + 1);
}

static assert (fullBits!1 == 1);
static assert (fullBits!2 == 3);
static assert (fullBits!3 == 7);
static assert (fullBits!4 == 15);
