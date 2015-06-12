/**
 * Tools for building up arrays without using the GC.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost, License 1.0)
 */

module memory.appender;

/**
 * Allocator-backed array appender.
 */
struct Appender(T, A, size_t initialSize = 10)
{
public:

	@disable this();
	@disable this(this);

	/**
	 * Params:
	 *     allocator = the allocator to use
	 */
	this()(auto ref A allocator)
	{
		this.allocator = allocator;
		mem = cast(T[]) allocator.allocate(initialSize * T.sizeof);
		assert (mem.length == initialSize);
	}

	/**
	 * Returns: all of the items
	 */
	T[] opSlice()
	{
		return mem[0 .. next];
	}

	alias put = append;

	/**
	 * Appends an item.
	 */
	void append(T item) @trusted
	{
		if (next >= mem.length)
		{
			next = mem.length;
			immutable newSize = T.sizeof * (mem.length << 1);
			void[] original = cast(void[]) mem;
			assert (original.ptr is mem.ptr);
			assert (mem);
			assert (original);
			assert (original.length == mem.length * T.sizeof);
			immutable bool success = allocator.reallocate(original, newSize);
			assert (success);
			mem = cast(T[]) original;
			assert (mem.ptr == original.ptr);
		}
		assert (next < mem.length);
		mem[next++] = item;
	}

	/**
	 * Appends several items.
	 */
	void append(inout(T)[] items) @trusted
	{
		foreach (ref i; items)
			append(i);
	}

	void reset()
	{
		next = 0;
	}

	T[] mem;

private:
	size_t next;
	A allocator;
}

unittest
{
	import std.experimental.allocator.mallocator : Mallocator;
	auto a = Appender!(int, shared Mallocator, 64)(Mallocator.it);
	foreach (i; 0 .. 20)
		a.append(i);
	assert (a[].length == 20);
	Mallocator.it.deallocate(a.mem);
}
