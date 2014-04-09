/**
 * Tools for building up arrays without using the GC.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module memory.appender;

/**
 * Allocator-backed array appender.
 */
struct Appender(T, A, size_t initialSize = 10)
{
public:

	@disable this();

	/**
	 * Params:
	 *     allocator = the allocator to use
	 */
	this(ref A allocator)
	{
		this.allocator = allocator;
		memory = cast(T[]) allocator.allocate(initialSize * T.sizeof);
		assert (memory.length == initialSize);
	}

	/**
	 * Returns: all of the items
	 */
	T[] opSlice()
	{
		return memory[0 .. next];
	}

	alias put = append;

	/**
	 * Appends an item.
	 */
	void append(T item) pure nothrow @trusted
	{
		import std.format;
		import std.traits: hasMember;
		if (next >= memory.length)
		{
			next = memory.length;
			immutable newSize = T.sizeof * (memory.length << 1);
			void[] original = cast(void[]) memory;
			assert (original.ptr is memory.ptr);
			assert (memory);
			assert (original);
			assert (original.length == memory.length * T.sizeof);
			bool success = allocator.reallocate(original, newSize);
			assert (success);
			memory = cast(T[]) original;
			assert (memory.ptr == original.ptr);
		}
		assert (next < memory.length);
		memory[next++] = item;
	}

	void reset()
	{
		next = 0;
	}

private:
	import memory.allocators;
	size_t next;
	T[] memory;
	A allocator;
}
