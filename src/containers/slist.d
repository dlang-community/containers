/**
 * Singly-linked list.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.slist;

auto slist(T)()
{
	import std.allocator;
	return SList!(T, shared Mallocator)(Mallocator.it);
}

/**
 * Single-linked allocator-backed list.
 * Params:
 *     T = the element type
 *     A = the allocator type
 * $(B Do not store pointers to GC-allocated memory in this container.)
 */
struct SList(T, A)
{
	/**
	 * Disable default-construction and postblit
	 */
	@disable this();
	/// ditto
	@disable this(this);

	/**
	 * Params: allocator = the allocator instance used to allocate nodes
	 */
	this(A allocator) pure nothrow
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
			deallocate(allocator, prev);
		}
	}

	/**
	 * Returns: the most recently inserted item
	 */
	T front() pure nothrow @property
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
		deallocate(allocator, f);
		return r;
	}

	/**
	 * Returns: true if this list is empty
	 */
	bool empty() pure nothrow const @property
	{
		return _front is null;
	}

	/**
	 * Returns: the number of items in the list
	 */
	size_t length() @property
	{
		return _length;
	}

	/**
	 * Inserts an item at the front of the list.
	 * Params: t = the item to insert into the list
	 */
	void insert(T t) pure nothrow @trusted
	{
		_front = allocate!Node(allocator, _front, t);
		_length++;
	}

	/// ditto
	alias insertFront = insert;

	/// ditto
	alias put = insert;

	void opOpAssign(string op)(T t) if (op == "~")
	{
		put(t);
	}

	/**
	 * Removes the first instance of value found in the list.
	 * Returns: true if a value was removed.
	 */
	bool remove(V)(V value) pure nothrow @trusted /+ if (is(T == V) || __traits(compiles, (T.init.opEquals(V.init))))+/
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
			deallocate(allocator, prev);
		}
		_front = null;
		_length = 0;
	}

private:

	import std.allocator;
	import memory.allocators;

	static struct Range
	{
	public:
		inout(T) front() inout pure nothrow @property
		{
			return cast(typeof(return)) current.value;
		}

		void popFront() pure nothrow
		{
			current = current.next;
		}

		bool empty() const pure nothrow @property
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
	import std.range;
	import std.allocator;
	import std.string;
	import std.algorithm;
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
