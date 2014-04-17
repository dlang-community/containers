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
 * $(B Do not store pointers to GC-allocated memory in this container.)
 */
struct UnrolledList(T, size_t cacheLineSize = 64)
{
	~this()
	{
		Node* prev = null;
		Node* cur = _front;
		while (cur !is null)
		{
			prev = cur;
			cur = cur.next;
			static if (!is(T == class))
				foreach (ref item; cur.items)
					typeid(T).destroy(&item);
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

	void remove(ref T item)
	{
		import core.bitop;
		Node* n = _front;
		while (n !is null)
		{
			foreach (i; 0 .. nodeCapacity)
			{
				if (n.items[i] == item)
				{
					n.markUnused(i);
					if (n.next !is null
						&& (popcnt(n.next.registry) + popcnt(n.registry) < nodeCapacity))
					{
						mergeNodes(n, n.next);
					}
				}
			}
		}
	}

	/// ditto
	alias put = insert;
	/// ditto
	alias insert = insertBack;

	/**
	 * Number of items stored per node.
	 */
	enum size_t nodeCapacity = (cacheLineSize - (void*).sizeof - (void*).sizeof
		- ushort.sizeof) / T.sizeof;
	static assert (nodeCapacity <= (typeof(Node.registry).sizeof * 8));

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
			this.current = current;
		}

		T front() const nothrow pure @property
		{
			return current.items[index];
		}

		void popFront() nothrow pure
		{
			index++;
			if (index >= nodeCapacity || current.isFree(index))
			{
				current = current.next;
				index = 0;
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

	Node* _back;
	Node* _front;
	size_t _length;

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
		{
			if (!first.isFree(j))
				temp[i++] = first.items[j];
			if (!second.isFree(j))
				temp[i++] = second.items[j];
		}
		first.next = second.next;
		first.items[0 .. i] = temp[0 .. i];
		first.registry = 0;
		foreach (k; 0 .. i)
			first.markUsed(k);
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
}
