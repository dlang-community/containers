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
 *     less = the comparitor function to use
 *     cacheLineSize = Nodes will be sized to fit within this number of bytes.
 * $(B Do not store pointers to GC-allocated memory in this container.)
 */
struct KAryTree(T, bool allowDuplicates = false, alias less = "a < b", size_t cacheLineSize = 64)
{
	this(this)
	{
		refCount++;
	}

	~this()
	{
		if (--refCount > 0)
			return;
		typeid(Node).destroy(root);
		deallocate(Mallocator.it, root);
	}

	enum size_t nodeCapacity = fatNodeCapacity!(T.sizeof, 2, cacheLineSize);

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

	bool insert(Range r)
	{
		bool retVal = false;
		while (!r.empty)
		{
			retVal = insert(r.front()) || retVal;
			r.popFront();
		}
		return retVal;
	}

	bool insert(T[] values)
	{
		bool retVal = false;
		foreach (ref v; values)
			retVal = insert(v) || retVal;
		return retVal;
	}

	bool remove(T value)
	{
		bool removed = root !is null && root.remove(value, root);
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

	Range opSlice()
	{
		return Range(root);
	}

	Range lowerBound(T value)
	{
		return Range(root, Range.Type.lower, value);
	}

	Range equalRange(T value)
	{
		return Range(root, Range.Type.equal, value);
	}

	Range upperBound(T value)
	{
		return Range(root, Range.Type.upper, value);
	}

	static struct Range
	{
		@disable this();

		T front()
		{
			return nodes.front.values[index];
		}

		bool empty () const nothrow pure @property
		{
			return _empty;
		}

		void popFront()
		{
			_popFront();
			if (empty)
				return;
			final switch (type)
			{
			case Type.upper:
			case Type.all: break;
			case Type.equal:
				if (front() != val)
					_empty = true;
				break;
			case Type.lower:
				if (!(front() < val))
					_empty = true;
				break;
			}
		}

		enum Type : ubyte {all, lower, equal, upper}

	private:

		this(Node* n)
		{
			if (n is null)
			{
				_empty = true;
				nodes = slist!(Node*)();
			}
			else
			{
				this.type = Type.all;
				nodes = SList!(Node*, shared Mallocator)(Mallocator.it);
				visit(n);
			}
		}

		this(Node* n, Type type, T val)
		{
			this(n);
			this.type = type;
			final switch(type)
			{
			case Type.all:
				break;
			case Type.lower:
				this.val = val;
				if (front() > val)
					_empty = true;
				break;
			case Type.equal:
				this.val = val;
				while (!empty() && front() < val)
					_popFront();
				break;
			case Type.upper:
				this.val = val;
				while (!empty() && front() <= val)
					_popFront();
				break;
			}
		}

		void _popFront()
		{
			index++;
			if (index >= nodeCapacity || nodes.front.isFree(index))
			{
				index = 0;
				nodes.popFront();
				if (nodes.empty)
				{
					_empty = true;
					return;
				}
			}
		}

		import containers.slist;
		import std.allocator;
		import memory.allocators;

		void visit(Node* n)
		{
			if (n.right !is null)
				visit(n.right);
			nodes.insertFront(n);
			if (n.left !is null)
				visit(n.left);
		}
		size_t index;
		SList!(Node*, shared Mallocator) nodes;
		Type type;
		bool _empty;
		T val;
	}

private:

	import std.allocator;
	import std.algorithm;
	import std.array;
	import containers.internal.fatnode;

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
			static if (!allowDuplicates)
				if (!assumeSorted(values[]).equalRange(value).empty)
					return false;
			T[nodeCapacity + 1] temp = void;
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

		bool remove(T value, ref Node* t)
		{
			import std.range;
			assert (registry != 0);
			if (value < values[0])
				return left !is null && left.remove(value, left);
			size_t i = nextAvailableIndex();
			if (value > values[i - 1])
				return right !is null && right.remove(value, right);
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
				values[$ - 1] = right.removeSmallest(right);
			if (registry == 0)
				t = null;
			return true;
		}

		T removeSmallest(ref Node* t)
		in
		{
			assert (registry != 0);
		}
		body
		{
			if (left is null && right is null)
			{
				T r = values[0];
				T[nodeCapacity - 1] temp = void;
				temp[] = values[1 .. $];
				values[0 .. $ - 1] = temp[];
				markUnused(nextAvailableIndex() - 1);

				if (registry == 0)
					t = null;
				return r;
			}
			if (left !is null)
				return left.removeSmallest(left);
			T r = values[0];
			T[nodeCapacity - 1] temp = void;
			temp[] = values[1 .. $];
			values[0 .. $ - 1] = temp[];
			values[$ - 1] = right.removeSmallest(right);
			if (registry == 0)
				t = null;
			return r;
		}

		T removeLargest(ref Node* t)
		in
		{
			assert (registry != 0);
		}
		body
		{
			if (left is null && right is null)
			{
				size_t i = nextAvailableIndex() - 1;
				markUnused(i);
				if (registry == 0)
					t = null;
				return values[i];
			}
			if (right !is null)
				return right.removeLargest(right);
			T r = values[$ - 1];
			T[nodeCapacity - 1] temp = void;
			temp[] = values[0 .. $ - 1];
			values[1 .. $] = temp[];
			values[0] = left.removeLargest(left);
			if (registry == 0)
				t = null;
			return r;
		}

		Node* rotate()
		{
			if (left is null && right is null)
				return &this;
			if (left !is null)
				left = left.rotate();
			if (right !is null)
				right = right.rotate();
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
			Node* retVal = void;
			if (right.left !is null && right.right is null)
			{
				retVal = right.left;
				retVal.right = right;
				retVal.left = &this;
				right.left = null;
				right = null;
			}
			else
			{
				retVal = right;
				right = retVal.left;
				retVal.left = &this;
			}
			fillFromChildren(retVal);
			if (retVal.left !is null)
			{
				fillFromChildren(retVal.left);
				retVal.left = retVal.left.rotate();
			}
			if (retVal.right !is null)
			{
				fillFromChildren(retVal.right);
				retVal.right = retVal.right.rotate();
			}
			return retVal;
		}

		Node* rotateRight()
		{
			Node* retVal = void;
			if (left.right !is null && left.left is null)
			{
				retVal = left.right;
				retVal.left = left;
				retVal.right = &this;
				left.right = null;
				left = null;
			}
			else
			{
				retVal = left;
				left = retVal.right;
				retVal.right = &this;
			}
			fillFromChildren(retVal);
			if (retVal.left !is null)
			{
				fillFromChildren(retVal.left);
				retVal.left = retVal.left.rotate();
			}
			if (retVal.right !is null)
			{
				fillFromChildren(retVal.right);
				retVal.right = retVal.right.rotate();
			}
			return retVal;
		}

		void fillFromChildren(Node* n)
		{
			while (!n.isFull())
			{
				if (n.left !is null)
					n.insert(n.left.removeLargest(n.left));
				else if (n.right !is null)
					n.insert(n.right.removeSmallest(n.right));
				else
					break;
			}
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

		invariant()
		{
			import std.string;
			assert (&this !is null);
			assert (left !is &this, "%x, %x".format(left, &this));
			assert (right !is &this, "%x, %x".format(right, &this));
			if (left !is null)
			{
				assert (left.left !is &this, "%s".format(values));
				assert (left.right !is &this, "%x, %x".format(left.right, &this));
			}
			if (right !is null)
			{
				assert (right.left !is &this, "%s".format(values));
				assert (right.right !is &this, "%s".format(values));
			}
		}

		Node* left;
		Node* right;
		T[nodeCapacity] values;
		ushort registry;
	}
	size_t _length;
	Node* root;
	uint refCount = 1;
}

unittest
{
	import std.uuid;
	import core.memory;
	import std.string;
	import std.range;
	import std.algorithm;
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
//			version(graphviz_debugging)
//			{
//				File f = File("graph%04d.dot".format(i), "w");
//				kt.print(f);
//			}
		}
		assert (kt.length == 200);
		assert (kt.remove(79));
		assert (!kt.remove(79));
//		version(graphviz_debugging)
//		{
//			File f = File("graph%04d.dot".format(999), "w");
//			kt.print(f);
//		}
		assert (kt.length == 199);
	}

	{
		string[] strs = [
			"2c381d2a-bacd-40db-b6d8-055b144c5ee6",
			"62104b50-e235-4c95-bcb9-a545e88e2d09",
			"828c8fc0-a392-4738-a49c-62e991fce090",
			"62e30465-79eb-446e-b34f-af5d7c491486",
			"93ec245b-60d2-4422-91ff-66a6d7e299fc",
			"c1d2f3d7-82cc-4d90-a2c5-9fba335f36cd",
			"c9d8d980-94eb-4941-b873-00d68021522f",
			"82dbc4df-cb3c-447a-9d73-cd6291a0ba02",
			"8d259231-6ab6-49e4-9bb6-fe097c4153ed",
			"f9f2d719-61e1-4f62-ae2c-bf2a24a13d5b"
		];
		KAryTree!string strings;
		foreach (i, s; strs)
		{
			assert (strings.insert(s));
//			version(graphviz_debugging)
//			{
//				File f = File("graph%04d.dot".format(i), "w");
//				strings.print(f);
//			}
		}
		sort(strs[]);
		assert (equal(strs, strings[]));
	}

	foreach (x; 0 .. 1000)
	{
		KAryTree!string strings;
		string[] strs = iota(10).map!(a => randomUUID().toString()).array();
		foreach (i, s; strs)
		{
			assert (strings.insert(s));
//			version(graphviz_debugging)
//			{
//				File f = File("graph%04d.dot".format(i), "w");
//				strings.print(f);
//			}
		}
		assert (strings.length == strs.length);
//		version(graphviz_debugging)
//		{
//			File f = File("graph%04d.dot".format(1000), "w");
//			strings.print(f);
//		}
		sort(strs);
		assert (equal(strs, strings[]));
	}

	{
		KAryTree!string strings;
		string[] strs = [
			"e",
			"f",
			"a",
			"b",
			"c",
			"d",
		];
		foreach (i, s; strs)
		{
			strings.insert(s);
			version(graphviz_debugging)
			{
				File f = File("graph%04d.dot".format(i), "w");
				strings.print(f);
			}
		}
		assert (equal(strings[], ["a", "b", "c", "d", "e", "f"]));
	}

	{
		KAryTree!(string, true) strings;
		assert (strings.insert("b"));
		assert (strings.insert("c"));
		assert (strings.insert("a"));
		assert (strings.insert("d"));
		assert (strings.insert("d"));
		assert (strings.length == 5);
		assert (equal(strings.equalRange("d"), ["d", "d"]));
		assert (equal(strings.lowerBound("d"), ["a", "b", "c"]));
		assert (equal(strings.upperBound("c"), ["d", "d"]));
	}
}
