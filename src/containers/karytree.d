/**
 * K-ary Tree.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.karytree;

version(graphviz_debugging) import std.stdio;

/**
 * K-ary tree Nodes are (by default) sized to fit within a 64-byte
 * cache line. The number of items stored per node can be read from the
 * nodeCapacity field. Each node 0, 1, or 2 children. Each node has between 1
 * and nodeCapacity items or nodeCapacity items and 0 or more children.
 * Params:
 *     T = the element type
 *     allowDuplicates = if true, duplicate values will be allowed in the tree
 *     cacheLineSize = Nodes will be sized to fit within this number of bytes.
 * $(B Do not store pointers to GC-allocated memory in this container.)
 */
struct KAryTree(T, bool allowDuplicates = false, size_t cacheLineSize = 64)
{
	enum size_t nodeCapacity = (cacheLineSize - ((void*).sizeof * 2) - ushort.sizeof) / T.sizeof;

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
		root = root.rotate();
		return r;
	}

	bool remove(T value)
	{
		bool removed = root !is null && root.remove(value);
		if (removed)
			--_length;
		return removed;
	}

	bool contains(T value) const nothrow pure
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

	version(graphviz_debugging) void print(File f)
	{
		f.writeln("digraph g {");
		root.print(f);
		f.writeln("}");
	}

private:

	import std.allocator;
	import std.algorithm;
	import std.array;

	static Node* allocateNode(ref T value)
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
		private size_t nextAvailableIndex() const nothrow pure
		{
			import core.bitop;
			return bsf(~registry);
		}

		private void markUsed(size_t index) pure nothrow
		{
			registry |= (1 << index);
		}

		private void markUnused(size_t index) pure nothrow
		{
			registry &= ~(1 << index);
		}

		private bool isFree(size_t index) const pure nothrow
		{
			return (registry & (1 << index)) == 0;
		}

		private bool isFull() const pure nothrow
		{
			return registry == fullBits!nodeCapacity;
		}

		bool contains(T value) const nothrow pure
		{
			import std.range;
			size_t i = nextAvailableIndex();
			if (value < values[0])
				return left !is null && left.contains(value);
			if (value > values[i - 1])
				return right !is null && right.contains(value);
			return !assumeSorted(values[0 .. i]).equalRange(value).empty;
		}

		int height() const nothrow pure
		{
			import std.algorithm;
			return 1 +
				max((left is null ? 0 : left.height()),
					(right is null ? 0 : right.height()));
		}

		bool insert(T value)
		{
			import std.range;
			if (!isFull())
			{
				immutable size_t index = nextAvailableIndex();
				static if (!allowDuplicates)
					if (!assumeSorted(values[0 .. index]).equalRange(value).empty)
						return false;
				values[index] = value;
				markUsed(index);
				sort(values[0 .. index + 1]);
				return true;
			}
			if (value < values[0])
			{
				if (left is null)
				{
					left = allocateNode(value);
					return true;
				}
				return left.insert(value);
			}
			if (value > values[$ - 1])
			{
				if (right is null)
				{
					right = allocateNode(value);
					return true;
				}
				return right.insert(value);
			}
			T[nodeCapacity + 1] temp = void;
			static if (!allowDuplicates)
				if (!assumeSorted(values[]).equalRange(value).empty)
					return false;
			temp[0 .. $ - 1] = values[];
			temp[$ - 1] = value;
			sort(temp[]);
			if (left is null)
			{
				values[] = temp[1 .. $];
				left = allocateNode(temp[0]);
				return true;
			}
			if (right is null)
			{
				values[] = temp[0 .. $ - 1];
				right = allocateNode(temp[$ - 1]);
				return true;
			}
			if (right.height < left.height)
			{
				values[] = temp[0 .. $ - 1];
				return right.insert(temp[$ - 1]);
			}
			values[] = temp[1 .. $];
			return left.insert(temp[0]);
		}

		bool remove(T value)
		{
			import std.range;
			if (registry == 0)
				return false;
			if (value < values[0])
				return left !is null && left.remove(value);
			size_t i = nextAvailableIndex();
			if (value > values[i - 1])
				return right !is null && right.remove(value);
			auto sv = assumeSorted(values[0 .. i]);
			auto tri = sv.trisect(value);
			if (tri[1].length == 0)
				return false;
			size_t l = tri[0].length;
			T[nodeCapacity - 1] temp;
			temp[0 .. l] = values[0 .. l];
			temp[l .. $] = values[l + 1 .. $];
			values[0 .. $ - 1] = temp[];
			if (right is null)
				markUnused(i - 1);
			else
				values[$ - 1] = right.removeSmallest();
			return true;
		}

		T removeSmallest()
		{
			if (left is null && right is null)
			{
				T r = values[0];
				T[nodeCapacity - 1] temp = void;
				temp[] = values[1 .. $];
				values[0 .. $ - 1] = temp[];
				markUnused(nodeCapacity - 1);
				return r;
			}
			if (left !is null)
				return left.removeSmallest();
			T r = values[0];
			T[nodeCapacity - 1] temp = void;
			temp[] = values[1 .. $];
			values[0 .. $ - 1] = temp[];
			values[$ - 1] = right.removeSmallest();
			markUnused(nodeCapacity - 1);
			return r;
		}

		Node* rotate()
		{
			if (left !is null)
				left = left.rotate();
			if (right !is null)
				right = right.rotate();
			if (left is null && right is null)
				return &this;
			if (left !is null
				&& ((right is null && left.height > 1)
				|| (right !is null && left.height > right.height + 1)))
			{
				return rotateRight();
			}
			if (right !is null
				&& ((left is null && right.height > 1)
				|| (left !is null && right.height > left.height + 1)))
			{
				return rotateLeft();
			}
			return &this;
		}

		Node* rotateLeft()
		{
			if (left is null)
			{
				Node* n = right;
				right.left = &this;
				right = null;
				return n;
			}
			Node* n = right.left;
			Node* r = right;
			right.left = &this;
			right = n;
			return r;
		}

		Node* rotateRight()
		{
			if (right is null)
			{
				Node* n = left;
				left.right = &this;
				left = null;
				return n;
			}
			Node* l = left;
			Node* n = left.right;
			left.right = &this;
			left = n;
			return l;
		}

		version(graphviz_debugging) void print(File f)
		{
			f.writef("\"%016x\"[shape=record, label=\"", &this);
			f.write("<f1>|");
			foreach (i, v; values)
			{
				if (isFree(i))
					f.write("<f> |");
				else
					f.writef("<f> %s|", v);
			}
			f.write("<f2>\"];");
			if (left !is null)
			{
				f.writefln("\"%016x\":f1 -> \"%016x\";", &this, left);
				left.print(f);
			}
			if (right !is null)
			{
				f.writefln("\"%016x\":f2 -> \"%016x\";", &this, right);
				right.print(f);
			}
		}

		Node* left;
		Node* right;
		T[nodeCapacity] values;
		ushort registry;
	}
	size_t _length;
	Node* root;
}

unittest
{
	import std.uuid;
	import core.memory;
	import std.string;
	GC.disable();
	scope(exit) GC.enable();

	{
		KAryTree!int kt;
		assert (kt.empty);
		foreach (i; 0 .. 200)
		{
			assert (kt.insert(i));
//			version(graphviz_debugging)
//			{
//				File f = File("graph%04d.dot".format(i), "w");
//				kt.print(f);
//			}
		}
		assert (!kt.empty);
		assert (kt.length == 200);
		assert (kt.contains(30));
	}

	{
		KAryTree!int kt;
		assert (!kt.contains(5));
		kt.insert(2_000);
		assert (kt.contains(2_000));
		foreach_reverse (i; 0 .. 1_000)
		{
			assert (kt.insert(i));
		}
		assert (!kt.contains(100_000));
	}

	{
		import std.random;
		KAryTree!int kt;
		foreach (i; 0 .. 1_000)
		{
			kt.insert(uniform(0, 100_000));
		}
	}

	{
		KAryTree!int kt;
		kt.insert(10);
		assert (kt.length == 1);
		assert (!kt.insert(10));
		assert (kt.length == 1);
	}

	{
		KAryTree!(int, true) kt;
		assert (kt.insert(1));
		assert (kt.length == 1);
		assert (kt.insert(1));
		assert (kt.length == 2);
		assert (kt.contains(1));
	}

	{
		KAryTree!(int) kt;
		foreach (i; 0 .. 200)
		{
			assert (kt.insert(i));
			version(graphviz_debugging)
			{
				File f = File("graph%04d.dot".format(i), "w");
				kt.print(f);
			}
		}
		assert (kt.length == 200);
		assert (kt.remove(79));
		assert (!kt.remove(79));
		version(graphviz_debugging)
		{
			File f = File("graph%04d.dot".format(999), "w");
			kt.print(f);
		}
		assert (kt.length == 199);
	}
}
