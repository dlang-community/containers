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
		import std.allocator : Mallocator, deallocate;
		foreach (ref bucket; buckets)
			typeid(typeof(bucket)).destroy(&bucket);
		static if (supportGC && shouldAddGCRange!T)
			GC.removeRange(buckets.ptr);
		Mallocator.it.deallocate(buckets);
	}

	/**
	 * Removes all items from the set
	 */
	void clear()
	{
		foreach (ref bucket; buckets)
			destroy(bucket);
		_length = 0;
	}

	/**
	 * Removes the given item from the set.
	 * Returns: false if the value was not present
	 */
	bool remove(T value)
	{
		hash_t hash = generateHash(value);
		size_t index = hashToIndex(hash);
		if (buckets[index].empty)
			return false;
		static if (storeHash)
			bool removed = buckets[index].remove(Node(hash, value));
		else
			bool removed = buckets[index].remove(Node(value));
		if (removed)
			--_length;
		return removed;
	}

	/**
	 * Returns: true if value is contained in the set.
	 */
	bool contains(T value) inout nothrow
	{
		if (buckets.length == 0)
			return false;
		hash_t hash = generateHash(value);
		size_t index = hashToIndex(hash);
		if (buckets[index].empty)
			return false;
		foreach (ref item; buckets[index].range)
		{
			static if (storeHash)
			{
				if (item.hash == hash && item.value == value)
					return true;
			}
			else
			{
				if (item.value == value)
					return true;
			}
		}
		return false;
	}

	/**
	 * Supports $(B a in b) syntax
	 */
	bool opBinaryRight(string op)(T value) inout nothrow if (op == "in")
	{
		return contains(value);
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
		hash_t hash = generateHash(value);
		size_t index = hashToIndex(hash);
		if (buckets[index].empty)
		{
	insert:
			static if (storeHash)
				buckets[index].insert(Node(hash, value));
			else
				buckets[index].insert(Node(value));
			++_length;
			if (shouldRehash())
				rehash();
			return true;
		}
		foreach (ref item; buckets[index].range)
		{
			static if (storeHash)
			{
				if (item.hash == hash && item.value == value)
					return false;
			}
			else
			{
				if (item.value == value)
					return false;
			}
		}
		goto insert;
	}

	/// ditto
	alias put = insert;

	/**
	 * Returns: true if the set has no items
	 */
	bool empty() inout nothrow pure @nogc @safe @property
	{
		return _length == 0;
	}

	/**
	 * Returns: the number of items in the set
	 */
	size_t length() inout nothrow pure @nogc @safe @property
	{
		return _length;
	}

	/**
	 * Forward range interface
	 */
	Range range() inout nothrow @nogc @safe @property
	{
		return Range(buckets);
	}

	/// ditto
	alias opSlice = range;

private:

	import containers.internal.node : shouldAddGCRange;
	import containers.unrolledlist : UnrolledList;
	import std.allocator : Mallocator, allocate;
	import std.traits : isBasicType;
	import core.memory : GC;

	enum bool storeHash = !isBasicType!T;

	void initialize(size_t bucketCount)
	{
		import std.conv : emplace;
		buckets = (cast(Bucket*) Mallocator.it.allocate(
			bucketCount * Bucket.sizeof))[0 .. bucketCount];
		assert (buckets.length == bucketCount);
		foreach (ref bucket; buckets)
			emplace(&bucket);
		static if (supportGC && shouldAddGCRange!T)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
	}

	static struct Range
	{
		this(const(Bucket)[] buckets)
		{
			this.buckets = buckets;
			if (buckets.length)
			{
				r = buckets[i].range;
				while (i < buckets.length && r.empty)
				{
					i++;
					r = buckets[i].range;
				}
			}
			else
				r = typeof(buckets[i].range()).init;
		}

		bool empty() const nothrow @safe @nogc @property
		{
			return i >= buckets.length;
		}

		T front() const nothrow @safe @nogc @property
		{
			return r.front.value;
		}

		void popFront()
		{
			r.popFront();
			while (r.empty)
			{
				i++;
				if (i >= buckets.length)
					return;
				r = buckets[i].range;
			}
		}

		const(Bucket)[] buckets;
		typeof(Bucket.range()) r;
		size_t i;
	}

	alias Bucket = UnrolledList!(Node, supportGC);

	bool shouldRehash() const pure nothrow @safe
	{
		return (cast(float) _length / cast(float) buckets.length) > 0.75;
	}

	void rehash() @trusted
	{
		import std.allocator : allocate, deallocate;
		import std.conv : emplace;
		immutable size_t newLength = buckets.length << 1;
		immutable size_t newSize = newLength * Bucket.sizeof;
		Bucket[] oldBuckets = buckets;
		buckets = (cast(Bucket*) Mallocator.it.allocate(newSize))[0 .. newLength];
		assert (buckets);
		assert (buckets.length == newLength);
		foreach (ref bucket; buckets)
			emplace(&bucket);
		static if (supportGC && shouldAddGCRange!T)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		foreach (ref const bucket; oldBuckets)
		{
			foreach (node; bucket.range)
			{
				static if (storeHash)
				{
					size_t index = hashToIndex(node.hash);
					buckets[index].put(Node(node.hash, node.value));
				}
				else
				{
					size_t hash = generateHash(node.value);
					size_t index = hashToIndex(hash);
					buckets[index].put(Node(node.value));
				}
			}
		}
		foreach (ref bucket; oldBuckets)
			typeid(Bucket).destroy(&bucket);
		static if (supportGC && shouldAddGCRange!T)
			GC.removeRange(oldBuckets.ptr);
		Mallocator.it.deallocate(oldBuckets);
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

	struct Node
	{
		bool opEquals(ref const T v) const
		{
			return v == value;
		}

		bool opEquals(ref const Node other) const
		{
			static if (storeHash)
				if (other.hash != hash)
					return false;
			return other.value == value;
		}

		static if (storeHash)
			hash_t hash;
		T value;
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
	assert (!s.contains("nonsense"));
	s.put("test");
	s.put("test");
	assert (s.contains("test"));
	assert (s.length == 1);
	assert (!s.contains("nothere"));
	s.put("a");
	s.put("b");
	s.put("c");
	s.put("d");
	string[] strings = s.range.array;
	assert (strings.canFind("a"));
	assert (strings.canFind("b"));
	assert (strings.canFind("c"));
	assert (strings.canFind("d"));
	assert (strings.canFind("test"));
	assert (strings.length == 5);
	assert (s.remove("test"));
	assert (s.length == 4);
	s.clear();
	assert (s.length == 0);
	assert (s.empty);
	s.put("abcde");
	assert (s.length == 1);
	foreach (i; 0 .. 10_000)
	{
		s.put(randomUUID().toString);
	}
	assert (s.length == 10_001);

	// Make sure that there's no range violation slicing an empty set
	HashSet!int e;
	foreach (i; e[])
		assert (i > 0);
}

private:

template HashSetAllocatorType(T)
{
	import memory.allocators;
	enum size_t hashSetNodeSize = (void*).sizeof + T.sizeof + hash_t.sizeof;
	enum size_t hashSetBlockSize = 512;
	alias HashSetAllocatorType = NodeAllocator!(hashSetNodeSize, hashSetBlockSize);
}
