module containers.internal.fatnode;

template fatNodeCapacity(size_t bytesPerItem, size_t pointerCount,
	size_t cacheLineSize = 64)
{
	enum size_t optimistic = (cacheLineSize
		- ((void*).sizeof * pointerCount) - ushort.sizeof) / bytesPerItem;
	static if (optimistic > 0)
		enum fatNodeCapacity = optimistic;
	else
		enum fatNodeCapacity = 1;
}
