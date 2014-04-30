/**
 * Unrolled Linked List.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.unrolledlist;

/**
 * Unrolled Linked List. Nodes are (by default) sized to fit within a 64-byte
 * cache line. The number of items stored per node can be read from the
 * nodeCapacity field.
 * See_also: $(Link http://en.wikipedia.org/wiki/Unrolled_linked_list)
 * Params:
 *     T = the element type
 *     cacheLineSize = Nodes will be sized to fit within this number of bytes.
 */
struct UnrolledList(T, size_t cacheLineSize = 64)
{
	this(this)
	{
		refCount++;
	}

	~this()
	{
		if (--refCount > 0)
			return;
		Node* prev = null;
		Node* cur = _front;
		while (cur !is null)
		{
			prev = cur;
			cur = cur.next;
			static if (!is(T == class))
				foreach (ref item; cur.items)
					typeid(T).destroy(&item);
			static if (shouldAddGCRange!T)
			{
				import core.memory;
				GC.removeRange(prev);
			}
			deallocate(Mallocator.it, prev);
		}
	}

	/**
	 * Inserts the given item into the end of the list.
	 */
	void insertBack(T item)
	{
		if (_back is null)
		{
			_back = allocate!Node(Mallocator.it);
			_front = _back;
		}
		size_t index = _back.nextAvailableIndex();
		if (index >= nodeCapacity)
		{
			Node* n = allocate!Node(Mallocator.it);
			_back.next = n;
			_back = n;
			index = 0;
		}
		_back.items[index] = item;
		_back.markUsed(index);
		_length++;
	}

	/// ditto
	alias put = insertBack;
	/// ditto
	alias insert = insertBack;

	void opOpAssign(string op)(T item) if (op == "~")
	{
		insertBack(item);
	}

	/**
	 * Inserts the given item in the frontmost available cell, which may put the
	 * item anywhere in the list as removal may leave gaps in list nodes. Use
	 * this only if the order of elements is not important.
	 */
	void insertAnywhere(T item)
	{
		Node* n = _front;
		while (_front !is null)
		{
			size_t i = n.nextAvailableIndex();
			if (i >= nodeCapacity)
			{
				if (n.next is null)
					break;
				n = n.next;
				continue;
			}
			n.items[i] = item;
			n.markUsed(i);
			_length++;
			return;
		}
		assert (n is _back);
		n = allocate!Node(Mallocator.it);
		static if (shouldAddGCRange!T)
		{
			import core.memory;
			GC.addRange(cast(void*) n, Node.sizeof);
		}
		_back.next = n;
		_back = n;
		_back.items[0] = item;
		_back.markUsed(0);
		_length++;
	}

	size_t length() const nothrow pure @property
	{
		return _length;
	}

	bool empty() const nothrow pure @property
	{
		return _length == 0;
	}

	bool remove(T item)
	{
		import core.bitop;
		if (_front is null)
			return false;
		Node* n = _front;
		bool r = false;
		loop: while (n !is null)
		{
			foreach (i; 0 .. nodeCapacity)
			{
				if (n.items[i] == item)
				{
					n.markUnused(i);
					r = true;
					--_length;
					if (n.next !is null
						&& (popcnt(n.next.registry) + popcnt(n.registry) <= nodeCapacity))
					{
						mergeNodes(n, n.next);
					}
					break loop;
				}
			}
			n = n.next;
		}
		if (_front.registry == 0)
		{
			_front = null;
			deallocate(Mallocator.it, _front);
		}
		return r;
	}

	void popFront()
	{
		moveFront();
	}

	T moveFront()
	in
	{
		assert (!empty());
		assert (_front.registry != 0);
	}
	body
	{
		import std.stdio;
		import core.bitop;
		size_t index = bsf(_front.registry);
		T r = _front.items[index];
		_front.markUnused(index);
		_length--;
		if (_front.registry == 0)
		{
			auto f = _front;
			_front = _front.next;
			deallocate(Mallocator.it, f);
			return r;
		}
		if (_front.next !is null
			&& (popcnt(_front.next.registry) + popcnt(_front.registry) <= nodeCapacity))
		{
			mergeNodes(_front, _front.next);
		}
		return r;
	}

	inout T front() inout @property
	{
		import core.bitop;
		size_t index = bsf(_front.registry);
		return _front.items[index];
	}

	/**
	 * Number of items stored per node.
	 */
	enum size_t nodeCapacity = fatNodeCapacity!(T.sizeof, 2, cacheLineSize);

	Range range()
	{
		return Range(_front);
	}

	alias opSlice = range;

	static struct Range
	{
		@disable this();
		this(Node* current)
		{
			import core.bitop;
			this.current = current;
			if (current !is null)
			{
				index = bsf(current.registry);
				assert (index < nodeCapacity);
			}
		}

		T front() @property
		{
			return current.items[index];
		}

		void popFront() nothrow pure
		{
			index++;
			while (true)
			{
				if (current is null)
					return;
				if (index >= nodeCapacity)
				{
					current = current.next;
					index = 0;
				}
				else
				{
					if (!current.isFree(index))
						return;
					index++;
				}
			}
		}

		bool empty() const nothrow pure @property
		{
			return current is null;
		}

		Node* current;
		size_t index;
	}

private:

	import std.allocator;
	import std.traits;
	import containers.internal.node;

	Node* _back;
	Node* _front;
	size_t _length;
	uint refCount = 1;

	void mergeNodes(Node* first, Node* second)
	in
	{
		assert (first !is null);
		assert (second is first.next);
	}
	body
	{
		import core.bitop;
		size_t i;
		T[nodeCapacity] temp;
		foreach (j; 0 .. nodeCapacity)
			if (!first.isFree(j))
				temp[i++] = first.items[j];
		foreach (j; 0 .. nodeCapacity)
			if (!second.isFree(j))
				temp[i++] = second.items[j];
		first.next = second.next;
		first.items[0 .. i] = temp[0 .. i];
		first.registry = 0;
		foreach (k; 0 .. i)
			first.markUsed(k);
		static if (shouldAddGCRange!T)
		{
			import core.memory;
			GC.removeRange(second);
		}
		deallocate(Mallocator.it, second);
	}

	static struct Node
	{
		size_t nextAvailableIndex() const nothrow pure
		{
			import core.bitop;
			return bsf(~registry);
		}

		void markUsed(size_t index)
		{
			registry |= (1 << index);
		}

		void markUnused(size_t index)
		{
			registry &= ~(1 << index);
			static if (shouldNullSlot!T)
				items[index] = null;
		}

		bool isFree(size_t index)
		{
			return (registry & (1 << index)) == 0;
		}

		ushort registry;
		T[nodeCapacity] items;
		Node* prev;
		Node* next;
	}
}

unittest
{
	import std.algorithm;
	import std.range;
	import std.stdio;
	import std.string;
	UnrolledList!int l;
	static assert (l.Node.sizeof <= 64);
	assert (l.empty);
	l.insert(0);
	assert (l.length == 1);
	assert (!l.empty);
	foreach (i; 1 .. 100)
		l.insert(i);
	assert (l.length == 100);
	assert (equal(l[], iota(100)));
	foreach (i; 0 .. 100)
		assert (l.remove(i), format("%d", i));
	assert (l.length == 0, format("%d", l.length));
	assert (l.empty);
	UnrolledList!int l2;
	l2.insert(1);
	l2.insert(2);
	l2.insert(3);
	assert (l2.front == 1);
	l2.popFront();
	assert (l2.front == 2);
	assert (equal(l2[], [2, 3]));
	l2.popFront();
	assert (equal(l2[], [3]));
	l2.popFront();
	assert (l2.empty, format("%d", l2.front));
	assert (equal(l2[], cast(int[]) []));
	UnrolledList!int l3;
	foreach (i; 0 .. 200)
		l3 ~= i;
	foreach (i; 0 .. 200)
	{
		auto x = l3.moveFront();
		assert (x == i, format("%d %d", i, x));
	}
	assert (l3.empty);
}
