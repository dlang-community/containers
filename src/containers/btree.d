/**
 * B-Tree.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.btree;

//version = graphviz_debugging;
version(graphviz_debugging) import std.stdio;

/**
 * B-Tree Nodes are (by default) sized to fit within a 64-byte
 * cache line. The number of items stored per node can be read from the
 * nodeCapacity field.
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

	static Node* allocateNode()
	{
		ubyte[] bytes = (cast(ubyte*) Mallocator.it.allocate(Node.sizeof))[0 .. Node.sizeof];
		bytes[] = 0;
		return cast(Node*) bytes.ptr;
	}

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

		private bool hasChildren() const nothrow pure
		{
			foreach (child; children)
				if (child !is null)
					return true;
			return false;
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

		size_t leftmostNonempty() const nothrow pure
		{
			foreach (i, child; children)
			{
				if (child is null)
					return size_t.max;
				if (!child.isFull())
					return i;
			}
			return size_t.max;
		}

//		invariant()
//		{
//			import core.bitop;
//			size_t index = bsf(~registry);
//			assert (isSorted(values[0 .. index]));
//			bool hc;
//			foreach (child; children)
//				if (child !is null)
//					hc = true;
//			if (hc)
//				assert (registry == fullBits!nodeCapacity);
//		}

		bool insert(T value)
		{
			immutable size_t index = nextAvailableIndex();
			if (!isFull())
			{
				values[index] = value;
				markUsed(index);
				sort(values[0 .. index + 1]);
				return true;
			}
			if (!hasChildren())
			{
				T[nodeCapacity + 1] temp;
				temp[0 .. $ - 1] = values[];
				temp[$ - 1] = value;
				sort(temp[]);
				values[] = temp[1 .. $];
				children[0] = allocateNode(temp[0]);
				return true;
			}
			if (value > values[$ - 1])
			{
				size_t i = leftmostNonempty();
				if (i == size_t.max)
				{
					foreach (k, ref child; children)
					{
						if (child is null)
						{
							i = k;
							child = allocateNode();
							goto leftDownShift;
						}
					}
					if (children[$ - 1] is null)
					{
						children[$ - 1] = allocateNode(value);
						return true;
					}
					else
						return children[$ - 1].insert(value);
				}
				else if (i + 1 == children.length)
				{
					children[i].insert(value);
					return true;
				}
			leftDownShift:
				T[nodeCapacity + 1] temp; // good
				immutable size_t rightLength = nodeCapacity - i; // good
				temp[0 .. rightLength] = values[i .. $]; // good
				temp[rightLength] = value;
				sort(temp[0 .. rightLength + 1]);
				children[i].insert(temp[0]);
				values[i .. $] = temp[1 .. rightLength + 1];
				return true;
			}
			else
			{
				foreach (i, ref v; values)
				{
					if (value < v && (value < values[i + 1]))
					{
						if (children[i] is null)
						{
							children[i] = allocateNode(value);
							return true;
						}
						else
							return children[i].insert(value);
					}
					else
					{
						T[nodeCapacity + 1] temp;
						temp[0 .. $ - i - 1] = values[i .. $];
						temp[$ - i - 1] = value;
						sort(temp[0 .. nodeCapacity - i + 1]);
						values[i .. $] = temp[1 .. nodeCapacity - i + 1];
						if (children[i] is null)
						{
							children[i] = allocateNode(temp[0]);
							return true;
						}
						else
							return children[i].insert(temp[0]);
					}
				}
			}
			return false;
		}

		version(graphviz_debugging) void print(File f)
		{
			f.writef("\"%016x\"[shape=record, label=\"", &this);
			foreach (i; 0 .. nodeCapacity)
			{
				f.writef("<f%d> |", (i * 2));
				f.writef("<f%d> %s|", (i * 2) + 1, values[i]);
				if (i + 1 == nodeCapacity)
					f.writef("<f%d> ", (i * 2) + 2);

			}
			f.writeln("\"];");
			foreach (i; 0 .. nodeCapacity)
			{
				if (children[i] !is null)
				{
					f.writefln("\"%016x\":f%d -> \"%016x\";", &this, (i * 2), children[i]);
					children[i].print(f);
				}
				if (i + 1 == nodeCapacity && children[i + 1] !is null)
				{
					f.writefln("\"%016x\":f%d -> \"%016x\";", &this, (i * 2) + 2, children[i + 1]);
					children[i + 1].print(f);
				}
			}
		}

		T[nodeCapacity] values;
		Node*[nodeCapacity + 1] children;
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

	BTree!string bt;
	auto names = [
		"A Song Across Wires",
		"These Hopeful Machines",
		"Laptop Symphony",
		"Letting Go",
		"Tomahawk",
		"Stem the Tides",
		"Love Divine",
		"Skylarking",
		"Calling Your Name",
		"City Life",
		"Lifeline",
		"This Binary Universe"
	];
	version(graphviz_debugging) foreach (i, name; names)
	{
		bt.insert(name);
		auto fn = format("/home/brian/tmp/graph%04d.dot", i);
		File f = File(fn, "w");
		bt.print(f);
	}

//	BTree!int ids;
//	version(graphviz_debugging) foreach (i; 0 .. 20)
//	{
//		assert (ids.insert(i));
//		auto fn = format("/home/brian/tmp/graph%04d.dot", i);
//		File f = File(fn, "w");
//		ids.print(f);
//	}
}
