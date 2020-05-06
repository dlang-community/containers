/**
 * Dynamic Array
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.dynamicarray;

private import containers.internal.node : shouldAddGCRange;
private import stdx.allocator.mallocator : Mallocator;

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

	private import stdx.allocator.common : stateSize;

	static if (is(typeof((T[] a, const T[] b) => a[0 .. b.length] = b[0 .. $])))
	{
		/// Either `const(T)` or `T`.
		alias AppendT = const(T);

		/// Either `const(typeof(this))` or `typeof(this)`.
		alias AppendTypeOfThis = const(typeof(this));
	}
	else
	{
		alias AppendT = T;
		alias AppendTypeOfThis = typeof(this);
	}

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
		do
		{
			this.allocator = allocator;
		}
	}

	~this()
	{
		import stdx.allocator.mallocator : Mallocator;
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
	void insertBack(T value)
	{
		import stdx.allocator.mallocator : Mallocator;
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
		import std.traits: hasElaborateAssign, hasElaborateDestructor;
		static if (is(T == struct) && (hasElaborateAssign!T || hasElaborateDestructor!T))
		{
			// If a destructor is run before blit or assignment involves
			// more than just a blit, ensure that arr[l] is in a valid
			// state before assigning to it.
			import core.stdc.string : memcpy, memset;
			const init = typeid(T).initializer();
			if (init.ptr is null) // null pointer means initialize to 0s
				(() @trusted => memset(arr.ptr + l, 0, T.sizeof))();
			else
				(() @trusted => memcpy(arr.ptr + l, init.ptr, T.sizeof))();
		}
		emplace(arr[l++], value);
	}

	/// ditto
	alias insert = insertBack;

	/// ditto
	alias insertAnywhere = insertBack;

	/// ditto
	alias put = insertBack;

	/**
	 * ~= operator overload
	 */
	scope ref typeof(this) opOpAssign(string op)(T value) if (op == "~")
	{
		insert(value);
		return this;
	}

	/**
	* ~= operator overload for an array of items
	*/
	scope ref typeof(this) opOpAssign(string op, bool checkForOverlap = true)(AppendT[] rhs)
		if (op == "~" && !is(T == AppendT[]))
	{
		// Disabling checkForOverlap when this function is called from opBinary!"~"
		// is not just for efficiency, but to avoid circular function calls that
		// would prevent inference of @nogc, etc.
		static if (checkForOverlap)
		if ((() @trusted => arr.ptr <= rhs.ptr && arr.ptr + arr.length > rhs.ptr)())
		{
			// Special case where rhs is a slice of this array.
			this = this ~ rhs;
			return this;
		}
		reserve(l + rhs.length);
		import std.traits: hasElaborateAssign, hasElaborateDestructor;
		static if (is(T == struct) && (hasElaborateAssign!T || hasElaborateDestructor!T))
		{
			foreach (ref value; rhs)
				emplace(arr[l++], value);
		}
		else
		{
			arr[l .. l + rhs.length] = rhs[0 .. rhs.length];
			l += rhs.length;
		}
		return this;
	}

	/// ditto
	scope ref typeof(this) opOpAssign(string op)(ref AppendTypeOfThis rhs)
		if (op == "~")
	{
		return this ~= rhs.arr[0 .. rhs.l];
	}

	/**
	 * ~ operator overload
	 */
	typeof(this) opBinary(string op)(ref AppendTypeOfThis other) if (op == "~")
	{
		typeof(this) ret;
		ret.reserve(l + other.l);
		ret.opOpAssign!("~", false)(arr[0 .. l]);
		ret.opOpAssign!("~", false)(other.arr[0 .. other.l]);
		return ret;
	}

	/// ditto
	typeof(this) opBinary(string op)(AppendT[] values) if (op == "~")
	{
		typeof(this) ret;
		ret.reserve(l + values.length);
		ret.opOpAssign!("~", false)(arr[0 .. l]);
		ret.opOpAssign!("~", false)(values);
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

	static if (is(typeof({T value;}))) // default construction is allowed
	{
		/**
		 * Change the array length.
		 * When growing, initialize new elements to the default value.
		 */
		void resize(size_t n)
		{
			resize(n, T.init);
		}
	}

	/**
	 * Change the array length.
	 * When growing, initialize new elements to the given value.
	 */
	void resize(size_t n, T value)
	{
		if (arr.length < n)
			reserve(n);

		if (l < n) // Growing?
		{
			import std.traits: hasElaborateAssign, hasElaborateDestructor;
			static if (is(T == struct) && (hasElaborateAssign!T || hasElaborateDestructor!T))
			{
				foreach (i; l..n)
					emplace(arr[l], value);
			}
			else
				arr[l..n] = value;
		}
		else
		{
			static if ((is(T == struct) || is(T == union))
				&& __traits(hasMember, T, "__xdtor"))
			{
				foreach (i; n..l)
					arr[i].__xdtor();
			}
		}

		l = n;
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

	static void emplace(ref ContainerStorageType!T target, ref AppendT source)
	{
		(cast(void[])((&target)[0..1]))[] = cast(void[])((&source)[0..1]);
		static if (__traits(hasMember, T, "__xpostblit"))
			target.__xpostblit();
	}

	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;
	import containers.internal.mixins : AllocatorState;

	enum bool useGC = supportGC && shouldAddGCRange!T;
	mixin AllocatorState!Allocator;
	ContainerStorageType!(T)[] arr;
	size_t l;
}

version(emsi_containers_unittest) unittest
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

version(emsi_containers_unittest)
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

version(emsi_containers_unittest) unittest
{
	int a = 0;
	{
		DynamicArray!(Cls) arr;
		arr.insert(new Cls( & a));
	}
	assert(a == 0); // Destructor not called.
}

version(emsi_containers_unittest) unittest
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

version(emsi_containers_unittest) unittest
{
	int a = 0;
	DynamicArray!(Cls, Mallocator, true) arr;
	arr.insert(new Cls(&a));

	arr.remove(0);
	assert(a == 0); // Destructor not called.
}

version(emsi_containers_unittest) unittest
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

version(emsi_containers_unittest) unittest
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

version(emsi_containers_unittest) @system unittest
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

version(emsi_containers_unittest) unittest
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

version(emsi_containers_unittest) @nogc unittest
{
	struct HStorage
	{
		import containers.dynamicarray: DynamicArray;
		DynamicArray!int storage;
	}
	auto hs = HStorage();
}

version(emsi_containers_unittest) @nogc unittest
{
	DynamicArray!char a;
	const DynamicArray!char b = a ~ "def";
	a ~= "abc";
	a ~= b;
	assert(a[] == "abcdef");
	a ~= a;
	assert(a[] == "abcdefabcdef");
}

version(emsi_containers_unittest) unittest
{
	static struct S
	{
		bool initialized;
		@nogc:
		@disable this();
		this(int) { initialized = true; }
		~this() { assert(initialized); }
	}

	auto s = S(0);

	DynamicArray!S arr;
	arr.insertBack(s);
	arr ~= [s];
}

version(emsi_containers_unittest) @nogc unittest
{
	DynamicArray!int a;
	a.resize(5, 42);
	assert(a.length == 5);
	assert(a[2] == 42);
	a.resize(3, 17);
	assert(a.length == 3);
	assert(a[2] == 42);

	struct Counter
	{
		@nogc:
		static int count;
		@disable this();
		this(int) { count++; }
		this(this) { count++; }
		~this() { count--; }
	}

	DynamicArray!Counter b;
	assert(Counter.count == 0);
	static assert(!is(typeof(b.resize(5))));
	b.resize(5, Counter(0));
	assert(Counter.count == 5);
	b.resize(3, Counter(0));
	assert(Counter.count == 3);
}
