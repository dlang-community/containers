/**
 * T-Tree.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.ttree;

import std.experimental.allocator.mallocator : Mallocator;
import std.range : ElementType, isInputRange;

/**
 * Implements a binary search tree with multiple items per tree node.
 *
 * T-tree Nodes are (by default) sized to fit within a 64-byte
 * cache line. The number of items stored per node can be read from the
 * nodeCapacity field. Each node has 0, 1, or 2 children. Each node has between
 * 1 and $(B nodeCapacity) items, or it has $(B nodeCapacity) items and 0 or
 * more children.
 * Params:
 *     T = the element type
 *     allowDuplicates = if true, duplicate values will be allowed in the tree
 *     less = the comparitor function to use
 *     cacheLineSize = Nodes will be sized to fit within this number of bytes.
 *     supportGC = true if the container should support holding references to
 *         GC-allocated memory.
 * See_also: $(LINK http://en.wikipedia.org/wiki/T-tree)
 */
struct TTree(T, Allocator = Mallocator, bool allowDuplicates = false,
	alias less = "a < b", bool supportGC = true, size_t cacheLineSize = 64)
{
	this(this) @disable;

	static if (stateSize!Allocator != 0)
	{
		/**
		 * Use `allocator` to allocate and free nodes in the tree.
		 */
		this(Allocator allocator)
		{
			this.allocator = allocator;
		}

		private alias AllocatorType = Allocator;
	}
	else
		alias AllocatorType = void*;

	~this()
	{
		if (root is null)
			return;
		deallocateNode(root, allocator);
	}

	enum size_t nodeCapacity = fatNodeCapacity!(T.sizeof, 3, size_t, cacheLineSize);
	static assert (nodeCapacity <= (size_t.sizeof * 4), "cannot fit height info and registry in size_t");

	debug(EMSI_CONTAINERS) invariant()
	{
		assert (root is null || _length != 0);
	}


	alias Value = ContainerStorageType!T;

	/// $(B tree ~= item) operator overload.
	void opOpAssign(string op)(T value) if (op == "~")
	{
		insert(value);
	}

	/**
	 * Returns true if any values were added. This is not a stable insert. You
	 * will get strange results if you insert into a tree while iterating over
	 * it.
	 */
	bool insert(T value)
	{
		if (root is null)
		{
			root = allocateNode(cast(Value) value, null, allocator);
			++_length;
			return true;
		}
		immutable bool r = root.insert(cast(Value) value, root, allocator);
		if (r)
			++_length;
		return r;
	}

	/// ditto
	bool insert(R)(R r) if (isInputRange!R && is(ElementType!R == T))
	{
		immutable bool retVal = false;
		while (!r.empty)
		{
			retVal = insert(r.front()) || retVal;
			r.popFront();
		}
		return retVal;
	}

	/// ditto
	bool insert(T[] values)
	{
		bool retVal = false;
		foreach (ref v; values)
			retVal = insert(v) || retVal;
		return retVal;
	}

	alias put = insert;

	/**
	 * Removes a value from the tree.
	 * Params:
	 *     value = a value equal to the one to be removed
	 *     cleanup = a function that should be run on the removed item
	 * Retuns: true if any value was removed
	 */
	bool remove(T value, void delegate(T) cleanup = null)
	{
		bool removed = root !is null && root.remove(cast(Value) value, root, allocator, cleanup);
		if (removed)
			--_length;
		if (_length == 0)
			deallocateNode(root, allocator);
		return removed;
	}

	/**
	 * Returns true if the tree _conains the given value
	 */
	bool contains(T value) const
	{
		return root !is null && root.contains(value);
	}

	/**
	 * Returns: the number of elements in the tree.
	 */
	size_t length() const nothrow pure @property
	{
		return _length;
	}

	/**
	 * Returns: true if the tree is empty.
	 */
	bool empty() const nothrow pure @property
	{
		return _length == 0;
	}

	/**
	 * Returns: a range over the tree. Do not insert into the tree while
	 * iterating because you may iterate over the same value multiple times.
	 */
	auto range(this This)()
	{
		return Range!(This)(cast(const(Node)*) root, RangeType.all, T.init);
	}

	alias opSlice = range;

	/**
	 * Returns: a range of elements which are less than value.
	 */
	auto lowerBound(this This)(inout T value)
	{
		return Range!(This)(cast(const(Node)*) root, RangeType.lower, value);
	}

	/**
	 * Returns: a range of elements which are equivalent (though not necessarily
	 * equal) to value.
	 */
	auto equalRange(this This)(inout T value)
	{
		return Range!(This)(cast(const(Node)*) root, RangeType.equal, value);
	}

	/**
	 * Returns: a range of elements which are greater than value.
	 */
	auto upperBound(this This)(inout T value)
	{
		return Range!(This)(cast(const(Node)*) root, RangeType.upper, value);
	}

	/**
	 * Tree range
	 */
	static struct Range(ThisT)
	{
		@disable this();

		/**
		 * Standard range operations
		 */
		ET front() const @property
		in
		{
			assert (!empty);
		}
		body
		{
			return cast(typeof(return)) current.values[index];
		}

		/// ditto
		bool empty() const nothrow pure @property
		{
			return current is null;
		}

		/// ditto
		void popFront()
		{
			_popFront();
			if (current is null)
				return;
			with (RangeType) final switch (type)
			{
			case upper:
			case all: break;
			case equal:
				if (_less(val, front()))
					current = null;
				break;
			case lower:
				if (!_less(front(), val))
					current = null;
				break;
			}
		}

	private:

		alias ET = ContainerElementType!(ThisT, T);

		void currentToLeftmost()
		{
			if (current is null)
				return;
			while (current.left !is null)
				current = current.left;
		}

		void currentToLeastContaining(inout T val)
		{
			if (current is null)
				return;
			while (current !is null)
			{
				assert(current.registry != 0);
				auto first = current.values[0];
				auto last = current.values[current.nextAvailableIndex - 1];
				immutable bool valLessFirst = _less(val, first);
				immutable bool valLessLast = _less(val, last);
				immutable bool firstLessVal = _less(first, val);
				immutable bool lastLessVal = _less(last, val);
				if (firstLessVal && valLessLast)
					return;
				else if (valLessFirst)
					current = current.left;
				else if (lastLessVal)
					current = current.right;
				else
				{
					static if (allowDuplicates)
					{
						if (!valLessFirst && !firstLessVal)
						{
							auto c = current;
							current = current.left;
							currentToLeastContaining(val);
							if (current is null)
								current = c;
							return;
						}
						else
							return;
					}
					else
						return;
				}

			}
		}

		this(inout(Node)* n, RangeType type, inout T val)
		{
			current = n;
			this.type = type;
			this.val = val;
			with (RangeType) final switch(type)
			{
			case all:
				currentToLeftmost();
				break;
			case lower:
				currentToLeftmost();
				if (_less(val, front()))
					current = null;
				break;
			case equal:
				currentToLeastContaining(val);
				while (current !is null && _less(front(), val))
					_popFront();
				if (current is null || _less(front(), val) || _less(val, front()))
					current = null;
				break;
			case upper:
				currentToLeastContaining(val);
				while (current !is null && !_less(val, front()))
					_popFront();
				break;
			}
		}

		void _popFront()
		in
		{
			assert (!empty);
		}
		body
		{
			index++;
			if (index >= nodeCapacity || current.isFree(index))
			{
				index = 0;
				if (current.right !is null)
				{
					current = current.right;
					while (current.left !is null)
						current = current.left;
				}
				else if (current.parent is null)
					current = null;
				else if (current.parent.left is current)
					current = current.parent;
				else
				{
					while (current.parent.right is current)
					{
						current = current.parent;
						if (current.parent is null)
						{
							current = null;
							return;
						}
					}
					current = current.parent;
				}
			}
		}

		size_t index;
		const(Node)* current;
		const RangeType type;
		const T val;
	}

private:

	import containers.internal.element_type : ContainerElementType;
	import containers.internal.node : fatNodeCapacity, fullBits, shouldAddGCRange, shouldNullSlot;
	import containers.internal.storage_type : ContainerStorageType;
	import std.algorithm : sort;
	import std.experimental.allocator.common : stateSize;
	import std.functional: binaryFun;
	import std.traits: isPointer, PointerTarget;

	enum RangeType : ubyte {all, lower, equal, upper}

	// If we're storing a struct that defines opCmp, don't compare pointers as
	// that is almost certainly not what the user intended.
	static if (is(typeof(less) == string ) && less == "a < b" && isPointer!T && __traits(hasMember, PointerTarget!T, "opCmp"))
		alias _less = binaryFun!"a.opCmp(*b) < 0";
	else
		alias _less = binaryFun!less;

	static Node* allocateNode(Value value, Node* parent, AllocatorType allocator)
	out (result)
	{
		assert (result.left is null);
		assert (result.right is null);
	}
	body
	{
		import core.memory : GC;
		import std.experimental.allocator : make;

		static if (stateSize!Allocator == 0)
			Node* n = make!Node(Allocator.instance);
		else
			Node* n = make!Node(allocator);
		n.parent = parent;
		n.markUsed(0);
		n.values[0] = cast(Value) value;
		static if (supportGC && shouldAddGCRange!T)
			GC.addRange(n, Node.sizeof);
		return n;
	}

	static void deallocateNode(ref Node* n, AllocatorType allocator)
	in
	{
		assert (n !is null);
	}
	body
	{
		import std.experimental.allocator : dispose;
		import core.memory : GC;

		if (n.left !is null)
			deallocateNode(n.left, allocator);
		if (n.right !is null)
			deallocateNode(n.right, allocator);

		static if (supportGC && shouldAddGCRange!T)
			GC.removeRange(n);
		static if (stateSize!Allocator == 0)
			dispose(Allocator.instance, n);
		else
			dispose(allocator, n);
		n = null;
	}

	static assert (nodeCapacity <= (typeof(Node.registry).sizeof * 8));
	static assert (Node.sizeof <= cacheLineSize);
	static struct Node
	{
		private size_t nextAvailableIndex() const nothrow pure
		{
			import core.bitop : bsf;
			return bsf(~(registry & fullBits!nodeCapacity));
		}

		private void markUsed(size_t index) pure nothrow
		{
			registry |= (1 << index);
		}

		private void markUnused(size_t index) pure nothrow
		{
			registry &= ~(1 << index);
			static if (shouldNullSlot!T)
				values[index] = null;
		}

		private bool isFree(size_t index) const pure nothrow
		{
			return (registry & (1 << index)) == 0;
		}

		private bool isFull() const pure nothrow
		{
			return (registry & fullBits!nodeCapacity) == fullBits!nodeCapacity;
		}

		private bool isEmpty() const pure nothrow
		{
			return (registry & fullBits!nodeCapacity) == 0;
		}

		bool contains(Value value) const
		{
			import std.range : assumeSorted;
			size_t i = nextAvailableIndex();
			if (_less(value, cast(Value) values[0]))
				return left !is null && left.contains(value);
			if (_less(values[i - 1], value))
				return right !is null && right.contains(value);
			return !assumeSorted!_less(values[0 .. i]).equalRange(value).empty;
		}

		size_t calcHeight() nothrow pure
		{
			immutable size_t l = left !is null ? left.height() : 0;
			immutable size_t r = right !is null ? right.height() : 0;
			size_t h = 1 + (l > r ? l : r);
			registry &= fullBits!nodeCapacity;
			registry |= (h << (size_t.sizeof * 4));
			return h;
		}

		size_t height() const nothrow pure
		{
			return registry >>> (size_t.sizeof * 4);
		}

		int imbalanced() const nothrow pure
		{
			if (right !is null
					&& ((left is null && right.height() > 1)
					|| (left !is null && right.height() > left.height() + 1)))
				return 1;
			if (left !is null
					&& ((right is null && left.height() > 1)
					|| (right !is null && left.height() > right.height() + 1)))
				return -1;
			return 0;
		}

		bool insert(T value, ref Node* root, AllocatorType allocator)
		in
		{
			static if (isPointer!T || is (T == class))
				assert (value !is null);
		}
		body
		{
			import std.algorithm : sort;
			import std.range : assumeSorted;
			if (!isFull())
			{
				immutable size_t index = nextAvailableIndex();
				static if (!allowDuplicates)
				{
					if (!assumeSorted!_less(values[0 .. index]).equalRange(
						cast(Value) value).empty)
					{
						return false;
					}
				}
				values[index] = cast(Value) value;
				markUsed(index);
				sort!_less(values[0 .. index + 1]);
				return true;
			}
			if (_less(value, values[0]))
			{
				if (left is null)
				{
					left = allocateNode(cast(Value) value, &this, allocator);
					calcHeight();
					return true;
				}
				bool b = left.insert(value, root, allocator);
				if (imbalanced() == -1)
					rotateRight(root, allocator);
				calcHeight();
				return b;
			}
			if (_less(values[$ - 1], cast(Value) value))
			{
				if (right is null)
				{
					right = allocateNode(value, &this, allocator);
					calcHeight();
					return true;
				}
				bool b = right.insert(value, root, allocator);
				if (imbalanced() == 1)
					rotateLeft(root, allocator);
				calcHeight();
				return b;
			}
			static if (!allowDuplicates)
				if (!assumeSorted!_less(values[]).equalRange(cast(Value) value).empty)
					return false;
			Value[nodeCapacity + 1] temp = void;
			temp[0 .. $ - 1] = values[];
			temp[$ - 1] = cast(Value) value;
			sort!_less(temp[]);
			if (right is null)
			{
				values[] = temp[0 .. $ - 1];
				right = allocateNode(temp[$ - 1], &this, allocator);
				return true;
			}
			if (left is null)
			{
				values[] = temp[1 .. $];
				left = allocateNode(temp[0], &this, allocator);
				return true;
			}
			if (right.height < left.height)
			{
				values[] = temp[0 .. $ - 1];
				bool b = right.insert(temp[$ - 1], root, allocator);
				if (imbalanced() == 1)
					rotateLeft(root, allocator);
				calcHeight();
				return b;
			}
			values[] = temp[1 .. $];
			bool b = left.insert(temp[0], root, allocator);
			if (imbalanced() == -1)
				rotateRight(root, allocator);
			calcHeight();
			return b;
		}

		bool remove(Value value, ref Node* n, AllocatorType allocator,
			void delegate(T) cleanup = null)
		{
			import std.range : assumeSorted;
			assert (!isEmpty());
			if (isFull() && _less(value, values[0]))
			{
				bool r = left !is null && left.remove(value, left, allocator, cleanup);
				if (left.isEmpty())
					deallocateNode(left, allocator);
				return r;
			}
			if (isFull() && _less(values[$ - 1], value))
			{
				bool r = right !is null && right.remove(value, right, allocator, cleanup);
				if (right.isEmpty())
					deallocateNode(right, allocator);
				return r;
			}
			size_t i = nextAvailableIndex();
			auto sv = assumeSorted!_less(values[0 .. i]);
			auto tri = sv.trisect(value);
			if (tri[1].length == 0)
				return false;
			// Clean up removed item
			if (cleanup !is null)
				cleanup(tri[1][0]);
			immutable size_t l = tri[0].length;
			if (right is null && left is null)
			{
				Value[nodeCapacity - 1] temp;
				temp[0 .. l] = values[0 .. l];
				temp[l .. $] = values[l + 1 .. $];
				values[0 .. $ - 1] = temp[];
				markUnused(nextAvailableIndex() - 1);
			}
			else if (right !is null)
			{
				Value[nodeCapacity - 1] temp;
				temp[0 .. l] = values[0 .. l];
				temp[l .. $] = values[l + 1 .. $];
				values[0 .. $ - 1] = temp[];
				values[$ - 1] = right.removeSmallest(allocator);
				if (right.isEmpty())
					deallocateNode(right, allocator);
			}
			else if (left !is null)
			{
				Value[nodeCapacity - 1] temp;
				temp[0 .. l] = values[0 .. l];
				temp[l .. $] = values[l + 1 .. $];
				values[1 .. $] = temp[];
				values[0] = left.removeLargest(allocator);
				if (left.isEmpty())
					deallocateNode(left, allocator);
			}
			return true;
		}

		Value removeSmallest(AllocatorType allocator)
		in
		{
			assert (!isEmpty());
		}
		body
		{
			if (left is null && right is null)
			{
				Value r = values[0];
				Value[nodeCapacity - 1] temp = void;
				temp[] = values[1 .. $];
				values[0 .. $ - 1] = temp[];
				markUnused(nextAvailableIndex() - 1);
				return r;
			}
			if (left !is null)
			{
				auto r = left.removeSmallest(allocator);
				if (left.isEmpty())
					deallocateNode(left, allocator);
				return r;
			}
			Value r = values[0];
			Value[nodeCapacity - 1] temp = void;
			temp[] = values[1 .. $];
			values[0 .. $ - 1] = temp[];
			values[$ - 1] = right.removeSmallest(allocator);
			if (right.isEmpty())
				deallocateNode(right, allocator);
			return r;
		}

		Value removeLargest(AllocatorType allocator)
		in
		{
			assert (!isEmpty());
		}
		out (result)
		{
			static if (isPointer!T || is (T == class))
				assert (result !is null);
		}
		body
		{
			if (left is null && right is null)
			{
				size_t i = nextAvailableIndex() - 1;
				Value r = values[i];
				markUnused(i);
				return r;
			}
			if (right !is null)
			{
				auto r = right.removeLargest(allocator);
				if (right.isEmpty())
					deallocateNode(right, allocator);
				return r;
			}
			Value r = values[$ - 1];
			Value[nodeCapacity - 1] temp = void;
			temp[] = values[0 .. $ - 1];
			values[1 .. $] = temp[];
			values[0] = left.removeLargest(allocator);
			if (left.isEmpty())
				deallocateNode(left, allocator);
			return r;
		}

		void rotateLeft(ref Node* root, AllocatorType allocator)
		{
			Node* newRoot = void;
			if (right.left !is null && right.right is null)
			{
				newRoot = right.left;
				newRoot.parent = this.parent;
				newRoot.left = &this;
				newRoot.left.parent = newRoot;
				newRoot.right = right;
				newRoot.right.parent = newRoot;
				newRoot.right.left = null;
				right = null;
				left = null;
			}
			else
			{
				newRoot = right;
				newRoot.parent = this.parent;
				right = newRoot.left;
				if (right !is null)
					right.parent = &this;
				newRoot.left = &this;
				this.parent = newRoot;
			}
			cleanup(newRoot, root, allocator);
		}

		void rotateRight(ref Node* root, AllocatorType allocator)
		{
			Node* newRoot = void;
			if (left.right !is null && left.left is null)
			{
				newRoot = left.right;
				newRoot.parent = this.parent;
				newRoot.right = &this;
				newRoot.right.parent = newRoot;
				newRoot.left = left;
				newRoot.left.parent = newRoot;
				newRoot.left.right = null;
				left = null;
				right = null;
			}
			else
			{
				newRoot = left;
				newRoot.parent = this.parent;
				left = newRoot.right;
				if (left !is null)
					left.parent = &this;
				newRoot.right = &this;
				this.parent = newRoot;
			}
			cleanup(newRoot, root, allocator);
		}

		void cleanup(Node* newRoot, ref Node* root, AllocatorType allocator)
		{
			if (newRoot.parent !is null)
			{
				if (newRoot.parent.right is &this)
					newRoot.parent.right = newRoot;
				else
					newRoot.parent.left = newRoot;
			}
			else
				root = newRoot;
			newRoot.fillFromChildren(root, allocator);
			if (newRoot.left !is null)
			{
				newRoot.left.fillFromChildren(root, allocator);
			}
			if (newRoot.right !is null)
			{
				newRoot.right.fillFromChildren(root, allocator);
			}
			if (newRoot.left !is null)
				newRoot.left.calcHeight();
			if (newRoot.right !is null)
				newRoot.right.calcHeight();
			newRoot.calcHeight();
		}

		void fillFromChildren(ref Node* root, AllocatorType allocator)
		{
			while (!isFull())
			{
				if (left !is null)
				{
					insert(left.removeLargest(allocator), root, allocator);
					if (left.isEmpty())
						deallocateNode(left, allocator);
				}
				else if (right !is null)
				{
					insert(right.removeSmallest(allocator), root, allocator);
					if (right.isEmpty())
						deallocateNode(right, allocator);
				}
				else
					return;
			}
		}

		debug(EMSI_CONTAINERS) invariant()
		{
			import std.string : format;
			assert (&this !is null);
			assert (left !is &this, "%x, %x".format(left, &this));
			assert (right !is &this, "%x, %x".format(right, &this));
			if (left !is null)
			{
				assert (left.left !is &this, "%s".format(values));
				assert (left.right !is &this, "%x, %x".format(left.right, &this));
				assert (left.parent is &this, "%x, %x, %x".format(left, left.parent, &this));
			}
			if (right !is null)
			{
				assert (right.left !is &this, "%s".format(values));
				assert (right.right !is &this, "%s".format(values));
				assert (right.parent is &this);
			}
		}

		Node* left;
		Node* right;
		Node* parent;

		Value[nodeCapacity] values;
		size_t registry = (cast(size_t) 1) << (size_t.sizeof * 4);
	}

	AllocatorType allocator;
	size_t _length = 0;
	Node* root = null;
}

unittest
{
	import core.memory : GC;
	import std.algorithm : equal, sort, map, filter, each;
	import std.array : array;
	import std.range : iota, walkLength, isInputRange;
	import std.string : format;
	import std.uuid : randomUUID;

	{
		TTree!int kt;
		assert (kt.empty);
		foreach (i; 0 .. 200)
			assert (kt.insert(i));
		assert (!kt.empty);
		assert (kt.length == 200);
		assert (kt.contains(30));
	}

	{
		TTree!int kt;
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
		import std.random : uniform;
		TTree!int kt;
		foreach (i; 0 .. 1_000)
			kt.insert(uniform(0, 100_000));
	}

	{
		TTree!int kt;
		kt.insert(10);
		assert (kt.length == 1);
		assert (!kt.insert(10));
		assert (kt.length == 1);
	}

	{
		TTree!(int, Mallocator, true) kt;
		assert (kt.insert(1));
		assert (kt.length == 1);
		assert (kt.insert(1));
		assert (kt.length == 2);
		assert (kt.contains(1));
	}

	{
		TTree!(int) kt;
		foreach (i; 0 .. 200)
			assert (kt.insert(i));
		assert (kt.length == 200);
		assert (kt.remove(79));
		assert (!kt.remove(79));
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
		TTree!string strings;
		foreach (i, s; strs)
			assert (strings.insert(s));
		sort(strs[]);
		assert (equal(strs, strings[]));
	}

	foreach (x; 0 .. 1000)
	{
		TTree!string strings;
		string[] strs = iota(10).map!(a => randomUUID().toString()).array();
		foreach (i, s; strs)
			assert (strings.insert(s));
		assert (strings.length == strs.length);
		sort(strs);
		assert (equal(strs, strings[]));
	}

	{
		TTree!string strings;
		strings.insert(["e", "f", "a", "b", "c", "d"]);
		assert (equal(strings[], ["a", "b", "c", "d", "e", "f"]));
	}

	{
		TTree!(string, Mallocator, true) strings;
		assert (strings.insert("b"));
		assert (strings.insert("c"));
		assert (strings.insert("a"));
		assert (strings.insert("d"));
		assert (strings.insert("d"));
		assert (strings.length == 5);
		assert (equal(strings.equalRange("d"), ["d", "d"]), format("%s", strings.equalRange("d")));
		assert (equal(strings.equalRange("a"), ["a"]), format("%s", strings.equalRange("a")));
		assert (equal(strings.lowerBound("d"), ["a", "b", "c"]), format("%s", strings.lowerBound("d")));
		assert (equal(strings.upperBound("c"), ["d", "d"]), format("%s", strings.upperBound("c")));
	}

	{
		static struct S
		{
			string x;
			int opCmp (ref const S other) const
			{
				if (x < other.x)
					return -1;
				if (x > other.x)
					return 1;
				return 0;
			}
		}

		TTree!(S*, Mallocator, true) stringTree;
		auto one = S("offset");
		stringTree.insert(&one);
		auto two = S("object");
		assert (stringTree.equalRange(&two).empty);
		assert (!stringTree.equalRange(&one).empty);
		assert (stringTree[].front.x == "offset");
	}

	{
		static struct TestStruct
		{
			int opCmp(ref const TestStruct other) const
			{
				return x < other.x ? -1 : (x > other.x ? 1 : 0);
			}
			int x;
			int y;
		}
		TTree!(TestStruct*) tsTree;
		static assert (isInputRange!(typeof(tsTree[])));
		foreach (i; 0 .. 100)
			assert(tsTree.insert(new TestStruct(i, i * 2)));
		assert (tsTree.length == 100);
		auto r = tsTree[];
		TestStruct* prev = r.front();
		r.popFront();
		while (!r.empty)
		{
			assert (r.front.x > prev.x, format("%s %s", prev.x, r.front.x));
			prev = r.front;
			r.popFront();
		}
		TestStruct a = TestStruct(30, 100);
		auto eqArray = array(tsTree.equalRange(&a));
		assert (eqArray.length == 1, format("%d", eqArray.length));
	}

	{
		import std.algorithm : canFind;
		TTree!int ints;
		foreach (i; 0 .. 50)
			ints ~= i;
		assert (canFind(ints[], 20));
		assert (walkLength(ints[]) == 50);
		assert (walkLength(filter!(a => (a & 1) == 0)(ints[])) == 25);
	}

	{
		TTree!int ints;
		foreach (i; 0 .. 50)
			ints ~=  i;
		ints.remove(0);
		assert (ints.length == 49);
		foreach (i; 1 .. 12)
			ints.remove(i);
		assert (ints.length == 49 - 11);
	}

	{
		const(TTree!(const(int))) getInts()
		{
			TTree!(const(int)) t;
			t.insert(1);
			t.insert(2);
			t.insert(3);
			return t;
		}
		auto t = getInts();
		static assert (is (typeof(t[].front) == const(int)));
		assert (equal(t[].filter!(a => a & 1), [1, 3]));
	}


	{
		static struct ABC
		{
			ulong a;
			ulong b;

			int opCmp(ref const ABC other) const
			{
				if (this.a < other.a)
					return -1;
				if (this.a > other.a)
					return 1;
				return 0;
			}
		}

		TTree!(ABC, Mallocator, true) tree;
		foreach (i; 0 .. 10)
			tree.insert(ABC(i));
		tree.insert(ABC(15));
		tree.insert(ABC(15));
		tree.insert(ABC(15));
		tree.insert(ABC(15));
		foreach (i; 20 .. 30)
			tree.insert(ABC(i));
		assert(tree.equalRange(ABC(15)).walkLength() == 4,
			format("Actual length = %d", tree.equalRange(ABC(15)).walkLength()));
	}

	{
		TTree!int ints2;
		iota(0, 1_000_000).each!(a => ints2.insert(a));
		assert(equal(iota(0, 1_000_000), ints2[]));
		assert(ints2.length == 1_000_000);
		foreach (i; 0 .. 1_000_000)
			assert(!ints2.equalRange(i).empty, format("Could not find %d", i));
	}

	{
		TTree!int ints3;
		foreach (i; iota(0, 1_000_000).filter!(a => a % 2 == 0))
			ints3.insert(i);
		assert(ints3.length == 500_000);
		foreach (i; iota(0, 1_000_000).filter!(a => a % 2 == 0))
			assert(!ints3.equalRange(i).empty);
		foreach (i; iota(0, 1_000_000).filter!(a => a % 2 == 1))
			assert(ints3.equalRange(i).empty);
	}

	{
		import std.experimental.allocator.building_blocks.free_list : FreeList;
		import std.experimental.allocator.building_blocks.allocator_list : AllocatorList;
		import std.experimental.allocator.building_blocks.region : Region;
		import std.experimental.allocator.building_blocks.stats_collector : StatsCollector;
		import std.stdio : stdout;

		StatsCollector!(FreeList!(AllocatorList!(a => Region!(Mallocator)(1024 * 1024)),
			64)) allocator;
		auto ints4 = TTree!(int, typeof(&allocator))(&allocator);
		foreach (i; 0 .. 10_000)
			ints4.insert(i);
		assert(walkLength(ints4[]) == 10_000);
		destroy(ints4);
		assert(allocator.numAllocate == allocator.numDeallocate);
		assert(allocator.bytesUsed == 0);
	}
}
