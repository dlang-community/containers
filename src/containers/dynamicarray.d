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
	import std.traits : hasMember;
	this(this) @disable;

	~this()
	{
		import std.experimental.allocator.mallocator : Mallocator;
		import containers.internal.node : shouldAddGCRange;

		if (arr is null)
			return;
		foreach (ref item; arr[0 .. l])
		{
			static if (is(T == class))
				destroy(item);
			else
				typeid(T).destroy(&item);
		}
		static if (shouldAddGCRange!T)
		{
			import core.memory : GC;
			GC.removeRange(arr.ptr);
		}
		Mallocator.instance.deallocate(arr);
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
	T opIndex(size_t i) @nogc
	{
		return arr[i];
	}

	/**
	 * Inserts the given value into the end of the array.
	 */
	void insert(T value)
	{
		import std.experimental.allocator.mallocator : Mallocator;
		import containers.internal.node : shouldAddGCRange;

		if (arr.length == 0)
		{
			arr = cast(T[]) Mallocator.instance.allocate(T.sizeof * 4);
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
			Mallocator.instance.reallocate(a, c * T.sizeof);
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

	void remove(const size_t i)
	{
		if (i < this.l)
		{
			static if (is(T == class))
				destroy(arr[i]);
			else
				typeid(T).destroy(&arr[i]);

			auto next = i + 1;
			while (next < this.l)
			{
				arr[next - 1] = arr[next];
				++next;
			}

			--l;
		}
		else
		{
			import core.exception : RangeError;
			throw new RangeError("Out of range index used to remove element");
		}
	}

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

	/**
	 * Returns: a slice to the underlying array.
	 *
	 * As the memory of the array may be freed, access to this array is
	 * highly unsafe.
	 */
	@property T* ptr() @nogc { return arr.ptr; }

private:

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

	auto arr = ints.ptr;
	arr[0] = 1337;
	assert(arr[0] == 1337);
	assert(ints[0] == 1337);
}

version(unittest)
{
	class Cls
	{
		int* a;

		this(int* a)
		{
			this.a = a;
		}

		~this()
		{
			++(*a);
		}
	}
}

unittest
{
	int a = 0;
	{
		DynamicArray!(Cls) arr;
		arr.insert(new Cls( & a));
	}
	assert(a == 1);
}

unittest
{
	import std.exception : assertThrown;
	import core.exception : RangeError;
	DynamicArray!int empty;
	assertThrown!RangeError(empty.remove(1337));
	assert(empty.length == 0);

	DynamicArray!int one;
	one.insert(0);
	assert(one.length == 1);
	assertThrown!RangeError(one.remove(1337));
	assert(one.length == 1);
	one.remove(0);
	assert(one.length == 0);

	DynamicArray!int two;
	two.insert(0);
	two.insert(1);
	assert(two.length == 2);
	assertThrown!RangeError(two.remove(1337));
	assert(two.length == 2);
	two.remove(0);
	assert(two.length == 1);
	assert(two[0] == 1);
	two.remove(0);
	assert(two.length == 0);

	two.insert(0);
	two.insert(1);
	assert(two.length == 2);

	two.remove(1);
	assert(two.length == 1);
	assert(two[0] == 0);
	assertThrown!RangeError(two.remove(1));
	assert(two.length == 1);
	assert(two[0] == 0);
	two.remove(0);
	assert(two.length == 0);
}

unittest
{
	int a = 0;
	DynamicArray!(Cls,true) arr;
	arr.insert(new Cls(&a));

	arr.remove(0);
	assert(a == 1);
}

unittest
{
	DynamicArray!(int*,true) arr;
	arr.insert(new int(1));
}
