/**
 * Hash Set
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.hashset;

import containers.internal.hash : generateHash;
import containers.internal.node : shouldAddGCRange;

/**
 * Hash Set.
 * Params:
 *     T = the element type
 *     hashFunction = the hash function to use on the elements
 */
struct HashSet(T, alias hashFunction = generateHash!T, bool supportGC = shouldAddGCRange!T)
{
	this(this) @disable;

	/**
	 * Constructs a HashSet with an initial bucket count of bucketCount.
	 * bucketCount must be a power of two.
	 */
	this(size_t bucketCount)
	in
	{
		assert ((bucketCount & (bucketCount - 1)) == 0, "bucketCount must be a power of two");
	}
	body
	{
		initialize(bucketCount);
	}

	~this()
	{
		import std.experimental.allocator.mallocator : Mallocator;
		import std.experimental.allocator : dispose;
		import core.memory : GC;
		static if (supportGC && shouldAddGCRange!T)
			GC.removeRange(buckets.ptr);
		Mallocator.instance.dispose(buckets);
	}

	/**
	 * Removes all items from the set
	 */
	void clear()
	{
		foreach (ref bucket; buckets)
		{
			destroy(bucket);
			bucket = Bucket.init;
		}
		_length = 0;
	}

	/**
	 * Removes the given item from the set.
	 * Returns: false if the value was not present
	 */
	bool remove(T value)
	{
		hash_t hash = hashFunction(value);
		size_t index = hashToIndex(hash);
		static if (storeHash)
			immutable bool removed = buckets[index].remove(Node(hash, value));
		else
			immutable bool removed = buckets[index].remove(Node(value));
		if (removed)
			--_length;
		return removed;
	}

	/**
	 * Returns: true if value is contained in the set.
	 */
	bool contains(T value) inout nothrow
	{
		return (value in this) !is null;
	}

	/**
	 * Supports $(B a in b) syntax
	 */
	inout(T)* opBinaryRight(string op)(T value) inout nothrow if (op == "in")
	{
		if (buckets.length == 0 || _length == 0)
			return null;
		hash_t hash = hashFunction(value);
		size_t index = hashToIndex(hash);
		return buckets[index].get(value, hash);
	}

	/**
	 * Inserts the given item into the set.
	 * Params: value = the value to insert
	 * Returns: true if the value was actually inserted, or false if it was
	 *     already present.
	 */
	bool insert(T value)
	{
		if (buckets.length == 0)
			initialize(4);
		hash_t hash = hashFunction(value);
		size_t index = hashToIndex(hash);
		static if (storeHash)
			auto r = buckets[index].insert(Node(hash, value));
		else
			auto r = buckets[index].insert(Node(value));
		if (r)
			++_length;
		if (shouldRehash)
			rehash();
		return r;
	}

	/// ditto
	alias put = insert;

	/**
	 * Returns: true if the set has no items
	 */
	bool empty() const nothrow pure @nogc @safe @property
	{
		return _length == 0;
	}

	/**
	 * Returns: the number of items in the set
	 */
	size_t length() const nothrow pure @nogc @safe @property
	{
		return _length;
	}

	/**
	 * Forward range interface
	 */
	auto range(this This)() nothrow @nogc @trusted @property
	{
		return Range!(This)(&this);
	}

	/// ditto
	alias opSlice = range;

private:

	import containers.internal.node : shouldAddGCRange, fatNodeCapacity;
	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;
	import containers.unrolledlist : UnrolledList;
	import std.traits : isBasicType, isPointer;

	enum ITEMS_PER_NODE = fatNodeCapacity!(Node.sizeof, 1, size_t, 128);

	enum bool storeHash = !isBasicType!T;

	void initialize(size_t bucketCount)
	{
		import std.experimental.allocator : makeArray;
		import std.experimental.allocator.mallocator : Mallocator;
		import core.memory : GC;

		buckets = Mallocator.instance.makeArray!Bucket(bucketCount);
		static if (supportGC && shouldAddGCRange!T)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
	}

	static struct Range(ThisT)
	{
		this(ThisT* t)
		{
			foreach (i, ref bucket; t.buckets)
			{
				bucketIndex = i;
				if (bucket.root !is null)
				{
					currentNode = cast(Bucket.BucketNode*) bucket.root;
					break;
				}
			}
			this.t = t;
		}

		bool empty() const nothrow @safe @nogc @property
		{
			return currentNode is null;
		}

		ET front() nothrow @safe @nogc @property
		{
			return cast(ET) currentNode.items[nodeIndex].value;
		}

		void popFront() nothrow @trusted @nogc
		{
			if (nodeIndex + 1 < currentNode.l)
			{
				++nodeIndex;
				return;
			}
			else
			{
				nodeIndex = 0;
				if (currentNode.next is null)
				{
					++bucketIndex;
					while (bucketIndex < t.buckets.length && t.buckets[bucketIndex].root is null)
						++bucketIndex;
					if (bucketIndex < t.buckets.length)
						currentNode = cast(Bucket.BucketNode*) t.buckets[bucketIndex].root;
					else
						currentNode = null;
				}
				else
				{
					currentNode = currentNode.next;
					assert(currentNode.l > 0);
				}
			}
		}

	private:
		alias ET = ContainerElementType!(ThisT, T);
		ThisT* t;
		Bucket.BucketNode* currentNode;
		size_t bucketIndex;
		size_t nodeIndex;
	}

	bool shouldRehash() const pure nothrow @safe @nogc
	{
		immutable float numberOfNodes = cast(float) _length / cast(float) ITEMS_PER_NODE;
		return (numberOfNodes / cast(float) buckets.length) > 0.75f;
	}

	void rehash() @trusted
	{
		import std.experimental.allocator : makeArray, dispose;
		import std.experimental.allocator.mallocator : Mallocator;
		import core.memory : GC;

		immutable size_t newLength = buckets.length << 1;
		Bucket[] oldBuckets = buckets;
		buckets = Mallocator.instance.makeArray!Bucket(newLength);
		assert (buckets);
		assert (buckets.length == newLength);
		static if (supportGC && shouldAddGCRange!T)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		foreach (ref const bucket; oldBuckets)
		{
			for (Bucket.BucketNode* node = cast(Bucket.BucketNode*) bucket.root; node !is null; node = node.next)
			{
				for (size_t i = 0; i < node.l; ++i)
				{
					static if (storeHash)
					{
						immutable size_t hash = node.items[i].hash;
						immutable size_t index = hashToIndex(hash);
						buckets[index].insert(Node(hash, node.items[i].value));
					}
					else
					{
						immutable size_t hash = hashFunction(node.items[i].value);
						immutable size_t index = hashToIndex(hash);
						buckets[index].insert(Node(node.items[i].value));
					}
				}
			}
		}
		static if (supportGC && shouldAddGCRange!T)
			GC.removeRange(oldBuckets.ptr);
		Mallocator.instance.dispose(oldBuckets);
	}

	size_t hashToIndex(hash_t hash) const pure nothrow @safe
	in
	{
		assert (buckets.length > 0);
	}
	out (result)
	{
		import std.string : format;
		assert (result < buckets.length, "%d, %d".format(result, buckets.length));
	}
	body
	{
		return hash & (buckets.length - 1);
	}

	static struct Bucket
	{
		this(this) @disable;

		~this()
		{
			import std.experimental.allocator : dispose;
			import std.experimental.allocator.mallocator : Mallocator;

			BucketNode* current = root;
			BucketNode* previous;
			while (true)
			{
				if (previous !is null)
					Mallocator.instance.dispose(previous);
				previous = current;
				if (current is null)
					break;
				current = current.next;
			}
		}

		static struct BucketNode
		{
			ContainerStorageType!(T)* get(Node n)
			{
				foreach (ref item; items[0 .. l])
				{
					static if (storeHash)
					{
						static if (isPointer!T)
						{
							if (item.hash == n.hash && *item.value == *n.value)
								return &item.value;
						}
						else
						{
							if (item.hash == n.hash && item.value == n.value)
								return &item.value;
						}
					}
					else
					{
						static if (isPointer!T)
						{
							if (*item.value == *n.value)
								return &item.value;
						}
						else
						{
							if (item.value == n.value)
								return &item.value;
						}
					}
				}
				return null;
			}

			void insert(Node n)
			{
				items[l] = n;
				++l;
			}

			bool remove(Node n)
			{
				import std.algorithm : SwapStrategy, remove;

				foreach (size_t i, ref node; items)
				{
					static if (storeHash)
					{
						static if (isPointer!T)
							immutable bool matches = node.hash == n.hash && *node.value == *n.value;
						else
							immutable bool matches = node.hash == n.hash && node.value == n.value;
					}
					else
					{
						static if (isPointer!T)
							immutable bool matches = *node.value == *n.value;
						else
							immutable bool matches = node.value == n.value;
					}
					if (matches)
					{
						items[].remove!(SwapStrategy.unstable)(i);
						l--;
						return true;
					}
				}
				return false;
			}

			BucketNode* next;
			size_t l;
			Node[ITEMS_PER_NODE] items;
		}

		bool insert(Node n)
		{
			import std.experimental.allocator : make;
			import std.experimental.allocator.mallocator : Mallocator;

			for (BucketNode* current = root; current !is null; current = current.next)
			{
				if (current.l >= current.items.length)
					continue;
				if (current.get(n))
					return false;
				current.insert(n);
				return true;
			}
			BucketNode* newNode = Mallocator.instance.make!BucketNode();
			newNode.insert(n);
			newNode.next = root;
			root = newNode;
			return true;
		}

		bool remove(Node n)
		{
			import std.experimental.allocator : dispose;
			import std.experimental.allocator.mallocator : Mallocator;

			BucketNode* current = root;
			BucketNode* previous;
			while (current !is null)
			{
				immutable removed = current.remove(n);
				if (removed)
				{
					if (current.l == 0)
					{
						if (previous !is null)
							previous.next = current.next;
						else
							root = null;
						Mallocator.instance.dispose(current);
					}
					return true;
				}
				previous = current;
				current = current.next;
			}
			return false;
		}

		inout(T)* get(T value, size_t hash) inout
		{
			for (BucketNode* current = cast(BucketNode*) root; current !is null; current = current.next)
			{
				static if (storeHash)
					auto v = current.get(Node(hash, value));
				else
					auto v = current.get(Node(value));
				if (v !is null)
					return cast(typeof(return)) v;
			}
			return null;
		}

		BucketNode* root;
	}

	static struct Node
	{
		bool opEquals(ref const T v) const
		{
			static if (isPointer!T)
				return *v == *value;
			else
				return v == value;
		}

		bool opEquals(ref const Node other) const
		{
			static if (storeHash)
				if (other.hash != hash)
					return false;
			static if (isPointer!T)
				return *other.value == *value;
			else
				return other.value == value;
		}

		static if (storeHash)
			hash_t hash;
		ContainerStorageType!T value;
	}

	Bucket[] buckets;
	size_t _length;
}

///
unittest
{
	import std.array : array;
	import std.algorithm : canFind;
	import std.uuid : randomUUID;

	auto s = HashSet!string(16);
	assert(!s.contains("nonsense"));
	assert(s.put("test"));
	assert(s.contains("test"));
	assert(!s.put("test"));
	assert(s.contains("test"));
	assert(s.length == 1);
	assert(!s.contains("nothere"));
	s.put("a");
	s.put("b");
	s.put("c");
	s.put("d");
	string[] strings = s.range.array;
	assert(strings.canFind("a"));
	assert(strings.canFind("b"));
	assert(strings.canFind("c"));
	assert(strings.canFind("d"));
	assert(strings.canFind("test"));
	assert(*("a" in s) == "a");
	assert(*("b" in s) == "b");
	assert(*("c" in s) == "c");
	assert(*("d" in s) == "d");
	assert(*("test" in s) == "test");
	assert(strings.length == 5);
	assert(s.remove("test"));
	assert(s.length == 4);
	s.clear();
	assert(s.length == 0);
	assert(s.empty);
	s.put("abcde");
	assert(s.length == 1);
	foreach (i; 0 .. 10_000)
	{
		s.put(randomUUID().toString);
	}
	assert(s.length == 10_001);

	// Make sure that there's no range violation slicing an empty set
	HashSet!int e;
	foreach (i; e[])
		assert(i > 0);

	enum MAGICAL_NUMBER = 600_000;

	HashSet!int f;
	foreach (i; 0 .. MAGICAL_NUMBER)
		assert(f.insert(i));
	import std.range:walkLength;
	assert(f.length == f[].walkLength);
	foreach (i; 0 .. MAGICAL_NUMBER)
		assert(i in f);
	foreach (i; 0 .. MAGICAL_NUMBER)
		assert(f.remove(i));
	foreach (i; 0 .. MAGICAL_NUMBER)
		assert(!f.remove(i));

	HashSet!int g;
	foreach (i; 0 .. MAGICAL_NUMBER)
		assert(g.insert(i));

	static struct AStruct
	{
		int a;
		int b;
	}

	HashSet!(AStruct*, a => a.a) fred;
	fred.insert(new AStruct(10, 10));
	auto h = new AStruct(10, 10);
	assert(h in fred);
}
