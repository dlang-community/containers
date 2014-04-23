/**
 * Dynamic Array
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.dynamicarray;

/**
 * Array that is able to grow itself when items are appended to it. Uses
 * reference counting to manage memory and malloc/free/realloc for managing its
 * storage.
 * Params:
 *     T = the array element type
 *     supportGC = true if the container should support holding references to
 *         GC-allocated memory.
 */
struct DynamicArray(T, bool supportGC = true)
{
	this(this)
	{
		refCount++;
	}

	~this()
	{
		if (--refCount > 0)
			return;
		foreach (ref item; arr[0 .. l])
			typeid(T).destroy(&item);
		static if (shouldAddGCRange!T)
		{
			import core.memory;
			GC.removeRange(arr.ptr);
		}
		Mallocator.it.deallocate(arr);
	}

	T[] opSlice()
	{
		return arr[0 .. l];
	}

	T[] opSlice(size_t a, size_t b)
	{
		return arr[a .. b];
	}

	T opIndex(size_t i)
	{
		return arr[i];
	}

	void insert(T value)
	{
		if (arr.length == 0)
		{
			arr = cast(T[]) Mallocator.it.allocate(T.sizeof * 4);
			static if (supportGC && shouldAddGCRange!T)
			{
				import core.memory;
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		else if (l >= arr.length)
		{
			immutable size_t c = arr.length > 512 ? arr.length + 1024 : arr.length << 1;
			void[] a = cast(void[]) arr;
			Mallocator.it.reallocate(a, c * T.sizeof);
			arr = cast(T[]) a;
			static if (supportGC && shouldAddGCRange!T)
			{
				import core.memory;
				GC.removeRange(arr.ptr);
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		arr[l++] = value;
	}

	alias put = insert;

	void opOpAssign(string op)(T value) if (op == "~")
	{
		insert(value);
	}

	void opIndexAssign(T value, size_t i)
	{
		arr[i] = value;
	}

	void opSliceAssign(T value)
	{
		arr[0 .. l] = value;
	}

	void opSliceAssign(T value, size_t i, size_t j)
	{
		arr[i .. j] = value;
	}

	size_t length() @property { return l; }

private:
	import std.allocator;
	import containers.internal.node;
	T[] arr;
	size_t l;
	uint refCount = 1;
}

unittest
{
	import std.stdio;
	import std.range;
	DynamicArray!int ints;
	foreach (i; 0 .. 100)
		ints ~= i;
	assert (equal(ints[], iota(100)));
	assert (ints.length == 100);
	ints[0] = 100;
	assert (ints[0] == 100);
	ints[0 .. 5] = 20;
	foreach (i; ints[0 .. 5])
		assert (i == 20);
	ints[] = 432;
	foreach (i; ints[])
		assert (i == 432);
	DynamicArray!int copy = ints;
}
