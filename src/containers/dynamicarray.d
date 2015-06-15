/**
 * Dynamic Array
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
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
	this(this) @disable;

	~this()
	{
		if (arr is null)
			return;
		foreach (ref item; arr[0 .. l])
			typeid(T).destroy(&item);
		static if (shouldAddGCRange!T)
		{
			import core.memory : GC;
			GC.removeRange(arr.ptr);
		}
		Mallocator.it.deallocate(arr);
	}

	/// Slice operator overload
	T[] opSlice() @nogc
	{
		return arr[0 .. l];
	}

	/// ditto
	T[] opSlice(size_t a, size_t b) @nogc
	{
		return arr[a .. b];
	}

	/// Index operator overload
	ref T opIndex(size_t i) @nogc
	{
		return arr[i];
	}

	/**
	 * Inserts the given value into the end of the array.
	 */
	void insert(T value)
	{
		if (arr.length == 0)
		{
			arr = cast(T[]) Mallocator.it.allocate(T.sizeof * 4);
			static if (supportGC && shouldAddGCRange!T)
			{
				import core.memory: GC;
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
				import core.memory: GC;
				GC.removeRange(arr.ptr);
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		arr[l++] = value;
	}

	/// ditto
	alias put = insert;

	/// Index assignment support
	void opIndexAssign(T value, size_t i) @nogc
	{
		arr[i] = value;
	}

	/// Slice assignment support
	void opSliceAssign(T value) @nogc
	{
		arr[0 .. l] = value;
	}

	/// ditto
	void opSliceAssign(T value, size_t i, size_t j) @nogc
	{
		arr[i .. j] = value;
	}

	/// Returns: the number of items in the array
	size_t length() const nothrow pure @property @safe @nogc { return l; }

private:
	import std.allocator: Mallocator;
	import containers.internal.node: shouldAddGCRange;
	T[] arr;
	size_t l;
}

unittest
{
	import std.algorithm : equal;
	import std.range : iota;
	DynamicArray!int ints;
	foreach (i; 0 .. 100)
		ints.insert(i);
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
}

unittest 
{
	DynamicArray!int ints;
	ints.insert(1); 

	int* oneP = &ints[0];
	*oneP = 1337;

	assert(ints[0] == 1337);
}
