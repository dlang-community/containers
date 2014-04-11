/**
 * B-Tree.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.btree;

/**
 * B-Tree Nodes are (by default) sized to fit within a 64-byte
 * cache line. The number of items stored per node can be read from the
 * nodeCapacity field.
 * See_also: $(Link http://en.wikipedia.org/wiki/Unrolled_linked_list)
 * Params:
 *     T = the element type
 *     allowDuplicates = if true, duplicate values will be allowed in the tree
 *     cacheLineSize = Nodes will be sized to fit within this number of bytes.
 * $(B Do not store pointers to GC-allocated memory in this container.)
 */
struct BTree(T, bool allowDuplicates = false, size_t cacheLineSize = 64)
{
	enum size_t nodeCapacity = (cacheLineSize - ushort.sizeof - (void*).sizeof)
		/ (T.sizeof + (void*).sizeof);

	bool insert(T value)
	{
		if (root is null)
		{
			root = allocateNode(value);
			++_length;
			return true;
		}
		bool r = root.insert(value);
		if (r)
			++_length;
		return r;
	}

	bool contains(ref T value) const nothrow pure
	{
		return root !is null && root.contains(value);
	}

	size_t length() const nothrow pure @property
	{
		return _length;
	}

	bool empty() const nothrow pure @property
	{
		return _length == 0;
	}

private:

	import std.allocator;
	import std.algorithm;
	import std.array;

	Node* allocateNode(ref T value)
	{
		ubyte[] bytes = (cast(ubyte*) Mallocator.it.allocate(Node.sizeof))[0 .. Node.sizeof];
		bytes[] = 0;
		Node* n = cast(Node*) bytes.ptr;
		n.markUsed(0);
		n.values[0] = value;
		return n;
	}

	template fullBits(size_t n, size_t c = 0)
	{
		static if (c >= (n - 1))
			enum fullBits = (1 << c);
		else
			enum fullBits = (1 << c) | fullBits!(n, c + 1);
	}

	static assert (fullBits!1 == 1);
	static assert (fullBits!2 == 3);
	static assert (fullBits!3 == 7);
	static assert (fullBits!4 == 15);
	static assert (nodeCapacity <= (typeof(Node.registry).sizeof * 8));
	static assert (Node.sizeof <= cacheLineSize);
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

		bool isFree(size_t index)
		{
			return (registry & (1 << index)) == 0;
		}

		bool isFull()
		{
			return registry == fullBits!nodeCapacity;
		}

		bool hasChildren()
		{
			foreach (child; children)
				if (child !is null)
					return false;
			return true;
		}

		bool contains(ref T value) const nothrow pure
		{
			foreach (i, ref v; values)
			{
				if (v < value)
					return children[i] !is null && children[i].contains(value);
				if (v == value)
					return true;
				if (i + 1 == nodeCapacity)
					return children[i + 1] !is null && children[i + 1].contains(value);
			}
			return false;
		}

		bool insert(T value)
		{
			if (!isFull())
			{
				immutable size_t index = nextAvailableIndex();
				values[index] = value;
				markUsed(index);
				sort(values[]);
				return true;
			}
			else if (!hasChildren)
			{
				T[nodeCapacity + 1] temp;
				temp[0 .. $ - 1] = values[];
				temp[$ - 1] = value;
				sort(temp[]);
				return true;
			}
			return false;
		}

		T[nodeCapacity] values;
		Node*[nodeCapacity + 1] children;
		ushort registry;
	}
	size_t _length;
	Node* root;
}

//unittest
//{
//	BTree!string bt;
//	bt.insert("A Song Across Wires");
//	bt.insert("These Hopeful Machines");
//	bt.insert("Laptop Symphony");
//	assert (bt.length == 3);
//	assert (!bt.empty);
//}
