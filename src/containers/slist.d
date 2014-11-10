/**
 * Singly-linked list.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.slist;

/**
 * Returns: A singly-linked list of type T backed by malloc().
 */
auto slist(T)()
{
	import std.allocator : Mallocator;
	return SList!(T, shared Mallocator)(Mallocator.it);
}

/**
 * Single-linked allocator-backed list.
 * Params:
 *     T = the element type
 *     A = the allocator type
 */
struct SList(T, A)
{
	/**
	 * Disable default-construction and postblit
	 */
	this() @disable;
	/// ditto
	this(this) @disable;

	/**
	 * Params: allocator = the allocator instance used to allocate nodes
	 */
	this(A allocator) pure nothrow @safe @nogc
	{
		this.allocator = allocator;
	}

	~this()
	{
		Node* current = _front;
		Node* prev = null;
		while (current !is null)
		{
			prev = current;
			current = current.next;
			typeid(Node).destroy(prev);
			static if (shouldAddGCRange!T)
			{
				import core.memory : GC;
				GC.removeRange(prev);
			}
			deallocate(allocator, prev);
		}
		_front = null;
	}

	/**
	 * Returns: the most recently inserted item
	 */
	T front() inout pure nothrow @property @safe @nogc
	in
	{
		assert (!empty);
	}
	body
	{
		return _front.value;
	}

	/**
	 * Removes and returns the first item in the list.
	 */
	T moveFront()
	in
	{
		assert (!empty);
	}
	body
	{
		Node* f = _front;
		_front = f.next;
		T r = f.value;
		static if (shouldAddGCRange!T)
		{
			import core.memory : GC;
			GC.removeRange(f);
		}
		deallocate(allocator, f);
		--_length;
		return r;
	}

	/**
	 * Removes the first item in the list.
	 */
	void popFront()
	{
		Node* f = _front;
		_front = f.next;
		static if (shouldAddGCRange!T)
		{
			import core.memory : GC;
			GC.removeRange(f);
		}
		deallocate(allocator, f);
		--_length;
	}

	/**
	 * Returns: true if this list is empty
	 */
	bool empty() inout pure nothrow @property @safe @nogc
	{
		return _front is null;
	}

	/**
	 * Returns: the number of items in the list
	 */
	size_t length() inout pure nothrow @property @safe @nogc
	{
		return _length;
	}

	/**
	 * Inserts an item at the front of the list.
	 * Params: t = the item to insert into the list
	 */
	void insert(T t) nothrow @trusted
	{
		_front = allocate!Node(allocator, _front, t);
		static if (shouldAddGCRange!T)
		{
			import core.memory : GC;
			GC.addRange(_front, Node.sizeof);
		}
		_length++;
	}

	/// ditto
	alias insertFront = insert;

	/// ditto
	alias put = insert;

	/// Supports $(B list ~= item) syntax
	void opOpAssign(string op)(T t) if (op == "~")
	{
		put(t);
	}

	/**
	 * Removes the first instance of value found in the list.
	 * Returns: true if a value was removed.
	 */
	bool remove(V)(V value) nothrow @trusted /+ if (is(T == V) || __traits(compiles, (T.init.opEquals(V.init))))+/
	{
		Node* prev = null;
		Node* cur = _front;
		while (cur !is null)
		{
			if (cur.value == value)
			{
				if (prev !is null)
					prev.next = cur.next;
				if (_front is cur)
					_front = cur.next;
				static if (shouldAddGCRange!T)
				{
					import core.memory : GC;
					GC.removeRange(cur);
				}
				deallocate(allocator, cur);
				_length--;
				return true;
			}
			prev = cur;
			cur = cur.next;
		}
		return false;
	}

	/**
	 * Forward range interface
	 */
	auto range() inout pure nothrow @property
	{
		return Range(_front);
	}

	/// ditto
	alias opSlice = range;

	/**
	 * Removes all elements from the range
	 */
	void clear()
	{
		Node* prev = null;
		Node* cur = _front;
		while (cur !is null)
		{
			prev = cur;
			cur = prev.next;
			static if (shouldAddGCRange!T)
			{
				import core.memory : GC;
				GC.removeRange(prev);
			}
			deallocate(allocator, prev);
		}
		_front = null;
		_length = 0;
	}

private:

	import std.allocator : allocate, deallocate;
	import memory.allocators : NodeAllocator;
	import containers.internal.node : shouldAddGCRange;

	static struct Range
	{
	public:
		inout(T) front() inout pure nothrow @property @trusted @nogc
		{
			return cast(typeof(return)) current.value;
		}

		void popFront() pure nothrow @safe @nogc
		{
			current = current.next;
		}

		bool empty() const pure nothrow @property @safe @nogc
		{
			return current is null;
		}

	private:
		const(Node)* current;
	}

	static struct Node
	{
		Node* next;
		T value;
	}

	Node* _front;

	A allocator;

	size_t _length;
}

unittest
{
	import std.allocator : CAllocatorImpl, Mallocator;
	import std.string : format;
	import std.algorithm : canFind;
	auto allocator = new CAllocatorImpl!(Mallocator);
	SList!(int, CAllocatorImpl!Mallocator) intList = SList!(int, CAllocatorImpl!(Mallocator))(allocator);
	foreach (i; 0 .. 100)
		intList.put(i);
	assert (intList.length == 100, "%d".format(intList.length));
	assert (intList.remove(10));
	assert (!intList.remove(10));
	assert (intList.length == 99);
	assert (intList.range.canFind(9));
	assert (!intList.range.canFind(10));
	auto l = slist!string();
	l ~= "abcde";
	l ~= "fghij";
	assert (l.length == 2);
}
