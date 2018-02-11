/**
 * Dynamic Array
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.dynamicarray;

private import containers.internal.node : shouldAddGCRange;
private import std.experimental.allocator.mallocator : Mallocator;

/**
 * Array that is able to grow itself when items are appended to it. Uses
 * malloc/free/realloc to manage its storage.
 *
 * Params:
 *     T = the array element type
 *     Allocator = the allocator to use. Defaults to `Mallocator`.
 *     supportGC = true if the container should support holding references to
 *         GC-allocated memory.
 */
struct DynamicArray(T, Allocator = Mallocator, bool supportGC = shouldAddGCRange!T)
{
	this(this) @disable;

	private import std.experimental.allocator.common : stateSize;

	static if (stateSize!Allocator != 0)
	{
		/// No default construction if an allocator must be provided.
		this() @disable;

		/**
		 * Use the given `allocator` for allocations.
		 */
		this(Allocator allocator)
		in
		{
			assert(allocator !is null, "Allocator must not be null");
		}
		body
		{
			this.allocator = allocator;
		}
	}

	~this()
	{
		import std.experimental.allocator.mallocator : Mallocator;
		import containers.internal.node : shouldAddGCRange;

		if (arr is null)
			return;

		static if ((is(T == struct) || is(T == union))
			&& __traits(hasMember, T, "__xdtor"))
		{
			foreach (ref item; arr[0 .. l])
			{
				item.__xdtor();
			}
		}
		static if (useGC)
		{
			import core.memory : GC;
			GC.removeRange(arr.ptr);
		}
		allocator.deallocate(arr);
	}

	/// Slice operator overload
	pragma(inline, true)
	auto opSlice(this This)() @nogc
	{
		return opSlice!(This)(0, l);
	}

	/// ditto
	pragma(inline, true)
	auto opSlice(this This)(size_t a, size_t b) @nogc
	{
		alias ET = ContainerElementType!(This, T);
		return cast(ET[]) arr[a .. b];
	}

	/// Index operator overload
	pragma(inline, true)
	auto opIndex(this This)(size_t i) @nogc
	{
		return opSlice!(This)(i, i + 1)[0];
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
			arr = cast(typeof(arr)) allocator.allocate(T.sizeof * 4);
			static if (useGC)
			{
				import core.memory: GC;
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		else if (l >= arr.length)
		{
			immutable size_t c = arr.length > 512 ? arr.length + 1024 : arr.length << 1;
			void[] a = cast(void[]) arr;
			allocator.reallocate(a, c * T.sizeof);
			arr = cast(typeof(arr)) a;
			static if (useGC)
			{
				import core.memory: GC;
				GC.removeRange(arr.ptr);
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		import std.traits: hasElaborateAssign, hasElaborateDestructor;
		static if (is(T == struct) && (hasElaborateAssign!T || hasElaborateDestructor!T))
		{
			// If a destructor is run before blit or copying involves
			// more than just a blit, ensure that arr[l] is in a valid
			// state before assigning to it.
			import core.stdc.string : memcpy, memset;
			const init = typeid(T).initializer();
			if (init.ptr is null) // null pointer means initialize to 0s
				(() @trusted => memset(arr.ptr + l, 0, T.sizeof))();
			else
				(() @trusted => memcpy(arr.ptr + l, init.ptr, T.sizeof))();
		}
		arr[l++] = value;
	}

	/// ditto
	alias put = insert;

	/**
	 * ~= operator overload
	 */
	void opOpAssign(string op)(T value) if (op == "~")
	{
		insert(value);
	}

	/**
	 * ~ operator overload
	 */
	typeof(this) opBinary(string op)(ref typeof(this) other) if (op == "~")
	{
		typeof(this) ret;
		ret.reserve(l + other.l);
		foreach (value; arr[0 .. l])
			ret.insert(value);
		foreach (value; other.arr[0 .. other.l])
			ret.insert(value);
		return ret;
	}

	/// ditto
	typeof(this) opBinary(string op)(T[] values) if (op == "~")
	{
		typeof(this) ret;
		ret.reserve(l + values.length);
		foreach (value; arr[0 .. l])
			ret.insert(value);
		foreach (value; values)
			ret.insert(value);
		return ret;
	}

	/**
	 * Ensures sufficient capacity to accommodate `n` elements.
	 */
	void reserve(size_t n)
	{
		if (arr.length >= n)
			return;
		if (arr.ptr is null)
		{
			size_t c = 4;
			if (c < n)
				c = n;
			arr = cast(typeof(arr)) allocator.allocate(T.sizeof * c);
			static if (useGC)
			{
				import core.memory: GC;
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
		else
		{
			size_t c = arr.length > 512 ? arr.length + 1024 : arr.length << 1;
			if (c < n)
				c = n;
			static if (useGC)
				void* oldPtr = arr.ptr;
			void[] a = cast(void[]) arr;
			allocator.reallocate(a, c * T.sizeof);
			arr = cast(typeof(arr)) a;
			static if (useGC)
			{
				import core.memory: GC;
				GC.removeRange(oldPtr);
				GC.addRange(arr.ptr, arr.length * T.sizeof);
			}
		}
	}

	/**
	 * Remove the item at the given index from the array.
	 */
	void remove(const size_t i)
	{
		if (i < this.l)
		{
			auto next = i + 1;
			while (next < this.l)
			{
				arr[next - 1] = arr[next];
				++next;
			}

			--l;
			static if ((is(T == struct) || is(T == union))
				&& __traits(hasMember, T, "__xdtor"))
			{
				arr[l].__xdtor();
			}
		}
		else
		{
			import core.exception : RangeError;
			throw new RangeError("Out of range index used to remove element");
		}
	}

	/**
     * Removes the last element from the array.
	 */
	void removeBack()
	{
		this.remove(this.length - 1);
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

	/// Ditto
	alias opDollar = length;

	/// Returns: whether or not the DynamicArray is empty.
	bool empty() const nothrow pure @property @safe @nogc { return l == 0; }

	/**
	 * Returns: a slice to the underlying array.
	 *
	 * As the memory of the array may be freed, access to this array is
	 * highly unsafe.
	 */
	auto ptr(this This)() @nogc @property
	{
		alias ET = ContainerElementType!(This, T);
		return cast(ET*) arr.ptr;
	}

	/// Returns: the front element of the DynamicArray.
	auto ref T front() pure @property
	{
		return arr[0];
	}

	/// Returns: the back element of the DynamicArray.
	auto ref T back() pure @property
	{
		return arr[l - 1];
	}

private:

	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;
	import containers.internal.mixins : AllocatorState;

	enum bool useGC = supportGC && shouldAddGCRange!T;
	mixin AllocatorState!Allocator;
	ContainerStorageType!(T)[] arr;
	size_t l;
}

unittest
{
	import std.algorithm : equal;
	import std.range : iota;
	DynamicArray!int ints;
	assert(ints.empty);
	foreach (i; 0 .. 100)
	{
		ints.insert(i);
		assert(ints.front == 0);
		assert(ints.back == i);
	}

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
	assert(a == 0); // Destructor not called.
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
	DynamicArray!(Cls, Mallocator, true) arr;
	arr.insert(new Cls(&a));

	arr.remove(0);
	assert(a == 0); // Destructor not called.
}

unittest
{
	DynamicArray!(int*, Mallocator, true) arr;

	foreach (i; 0 .. 4)
		arr.insert(new int(i));

	assert (arr.length == 4);

	int*[] slice = arr[1 .. $ - 1];
	assert (slice.length == 2);
	assert (*slice[0] == 1);
	assert (*slice[1] == 2);
}

unittest
{
	import std.format : format;

	DynamicArray!int arr;
	foreach (int i; 0 .. 10)
		arr ~= i;
	assert(arr.length == 10, "arr.length = %d".format(arr.length));

	auto arr2 = arr ~ arr;
	assert(arr2.length == 20);
	auto arr3 = arr2 ~ [100, 99, 98];
	assert(arr3.length == 23);

	while(!arr3.empty)
		arr3.removeBack();
	assert(arr3.empty);

}

@system unittest
{
    DynamicArray!int a;
    a.reserve(1000);
    assert(a.length == 0);
    assert(a.empty);
    assert(a.arr.length >= 1000);
    int* p = a[].ptr;
    foreach (i; 0 .. 1000)
    {
        a.insert(i);
    }
    assert(p is a[].ptr);
}

unittest
{
	// Ensure that Array.insert doesn't call the destructor for
	// a struct whose state is uninitialized memory.
	static struct S
	{
		int* a;
		~this() @nogc nothrow
		{
			if (a !is null)
				++(*a);
		}
	}
	int a = 0;
	DynamicArray!S arr;
	// This next line may segfault if destructors are called
	// on structs in invalid states.
	arr.insert(S(&a));
	assert(a == 1);
}

@nogc unittest
{
    struct HStorage
    {
	    import containers.dynamicarray: DynamicArray;
	    DynamicArray!int storage;
    }
	auto hs = HStorage();
}

