/**
 * Hash Map
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.hashmap;

import containers.internal.hash : generateHash;
import containers.internal.node : shouldAddGCRange;

/**
 * Associative array / hash map.
 * Params:
 *     K = the key type
 *     V = the value type
 *     hashFunction = the hash function to use on the keys
 */
struct HashMap(K, V, alias hashFunction = generateHash!K,
	bool supportGC = shouldAddGCRange!K || shouldAddGCRange!V)
{
	this(this) @disable;

	/**
	 * Constructs an HashMap with an initial bucket count of bucketCount. bucketCount
	 * must be a power of two.
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
		static if (supportGC)
			GC.removeRange(buckets.ptr);
		Mallocator.it.deallocate(buckets);
	}

	/**
	 * Supports $(B aa[key]) syntax.
	 */
	V opIndex(K key) const
	{
		import std.algorithm : find;
		import std.exception : enforce;
		import std.conv : text;
		if (buckets.length == 0)
			throw new Exception("'" ~ text(key) ~ "' not found in HashMap");
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (r; buckets[index].range)
		{
			static if (storeHash)
			{
				if (r.hash == hash && r == key)
					return r.value;
			}
			else
			{
				if (r == key)
					return r.value;
			}
		}
		throw new Exception("'" ~ text(key) ~ "' not found in HashMap");
	}

	/**
	 * Supports $(B aa[key] = value;) syntax.
	 */
	void opIndexAssign(V value, K key)
	{
		insert(key, value);
	}

	/**
	 * Supports $(B key in aa) syntax.
	 */
	V* opBinaryRight(string op)(K key) const nothrow if (op == "in")
	{
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (ref node; buckets[index].range)
		{
			static if (storeHash)
			{
				if (node.hash == hash && node == key)
					return &node.value;
			}
			else
			{
				if (node == key)
					return &node.value;
			}
		}
		return null;
	}

	/**
	 * Removes the value associated with the given key
	 * Returns: true if a value was actually removed.
	 */
	bool remove(K key)
	{
		if (buckets.length == 0)
			return false;
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		static if (storeHash)
			bool removed = buckets[index].remove(Node(hash, key));
		else
			bool removed = buckets[index].remove(Node(key));
		if (removed)
			_length--;
		return removed;
	}

	/**
	 * Returns: the number of key/value pairs in this aa
	 */
	size_t length() const nothrow pure @property @safe @nogc
	{
		return _length;
	}

	/**
	 * Returns: a GC-allocated array filled with the keys contained in this map.
	 */
	K[] keys() const @property
	out(result)
	{
		assert (result.length == _length);
	}
	body
	{
		import std.array : appender;
		auto app = appender!(K[])();
		foreach (ref const bucket; buckets)
		{
			foreach (item; bucket.range)
				app.put(item.key);
		}
		return app.data;
	}

	/**
	 * Returns: a GC-allocated array containing the values contained in this map.
	 */
	V[] values() const @property
	out(result)
	{
		assert (result.length == _length);
	}
	body
	{
		import std.array : appender;
		auto app = appender!(V[])();
		foreach (ref const bucket; buckets)
		{
			foreach (item; bucket.range)
				app.put(item.value);
		}
		return app.data;
	}

	/**
	 * Support for $(D foreach(key, value; aa) { ... }) syntax;
	 */
	int opApply(int delegate(ref K, ref V) del)
	{
		int result = 0;
		foreach (ref bucket; buckets)
		{
			foreach (ref node; bucket.range)
			{
				result = del(node.key, node.value);
				if (result != 0)
					return result;
			}
		}
		return result;
	}

private:

	import std.allocator : Mallocator, allocate;
	import std.traits : isBasicType;
	import containers.unrolledlist : UnrolledList;
	import core.memory : GC;

	enum bool storeHash = !isBasicType!K;

	void initialize(size_t bucketCount = 4)
	{
		import std.conv : emplace;
		import std.allocator : allocate;
		buckets = (cast(Bucket*) Mallocator.it.allocate( // Valgrind
			bucketCount * Bucket.sizeof))[0 .. bucketCount];
		assert (buckets.length == bucketCount);
		static if (supportGC)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		foreach (ref bucket; buckets)
			emplace(&bucket);
	}

	void insert(K key, V value)
	{
		if (buckets.length == 0)
			initialize();
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (ref item; buckets[index].range)
		{
			static if (storeHash)
			{
				if (item.hash == hash && item.key == key)
				{
					item.value = value;
					return;
				}
			}
			else
			{
				if (item.key == key)
				{
					item.value = value;
					return;
				}
			}
		}
		static if (storeHash)
			buckets[index].put(Node(hash, key, value));
		else
			buckets[index].put(Node(key, value));
		_length++;
		if (shouldRehash)
			rehash();
	}

	/**
	 * Returns: true if the load factor has been exceeded
	 */
	bool shouldRehash() const pure nothrow @safe @nogc
	{
		return cast(float) _length / cast(float) buckets.length > 0.75;
	}

	/**
	 * Rehash the map.
	 */
	void rehash() @trusted
	{
		import std.allocator : allocate, deallocate;
		import std.conv : emplace;
		immutable size_t newLength = buckets.length << 1;
		immutable size_t newSize = newLength * Bucket.sizeof;
		Bucket[] oldBuckets = buckets;
		assert (oldBuckets.ptr == buckets.ptr);
		buckets = cast(Bucket[]) Mallocator.it.allocate(newSize);
		static if (supportGC)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		assert (buckets);
		assert (buckets.length == newLength);
		foreach (ref bucket; buckets)
			emplace(&bucket);
		foreach (ref bucket; oldBuckets)
		{
			foreach (node; bucket.range)
			{
				static if (storeHash)
				{
					size_t index = hashToIndex(node.hash);
					buckets[index].put(Node(node.hash, node.key, node.value));
				}
				else
				{
					size_t hash = generateHash(node.key);
					size_t index = hashToIndex(hash);
					buckets[index].put(Node(node.key, node.value));
				}
			}
			typeid(typeof(bucket)).destroy(&bucket);
		}
		static if (supportGC)
			GC.removeRange(oldBuckets.ptr);
		Mallocator.it.deallocate(cast(void[]) oldBuckets);
	}

	size_t hashToIndex(size_t hash) const pure nothrow @safe @nogc
	in
	{
		assert (buckets.length > 0);
	}
	out (result)
	{
		assert (result < buckets.length);
	}
	body
	{
		return hash & (buckets.length - 1);
	}

	size_t hashIndex(K key) const
	out (result)
	{
		assert (result < buckets.length);
	}
	body
	{
		return hashToIndex(generateHash(key));
	}

	struct Node
	{
		bool opEquals(ref const K key) const
		{
			return key == this.key;
		}

		bool opEquals(ref const Node n) const
		{
			static if (storeHash)
				return this.hash == n.hash && this.key == n.key;
			else
				return this.key == n.key;
		}

		static if (storeHash)
			size_t hash;
		K key;
		V value;
	}

	alias Bucket = UnrolledList!(Node, supportGC);
	Bucket[] buckets;
	size_t _length;
}

///
unittest
{
	import std.uuid : randomUUID;
	auto hm = HashMap!(string, int)(16);
	assert (hm.length == 0);
	assert (!hm.remove("abc"));
	hm["answer"] = 42;
	assert (hm.length == 1);
	assert ("answer" in hm);
	hm.remove("answer");
	assert (hm.length == 0);
	hm["one"] = 1;
	hm["one"] = 1;
	assert (hm.length == 1);
	assert (hm["one"] == 1);
	foreach (i; 0 .. 1000)
	{
		hm[randomUUID().toString] = i;
	}
	assert (hm.length == 1001);
	assert (hm.keys().length == hm.length);
	assert (hm.values().length == hm.length);
	foreach (ref k, ref v; hm) {}

	auto hm2 = HashMap!(char, char)(4);
	hm2['a'] = 'a';
}
