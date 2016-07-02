/**
 * Hash Map
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.hashmap;

private import containers.internal.hash : generateHash;
private import containers.internal.node : shouldAddGCRange;
private import std.experimental.allocator.mallocator : Mallocator;

/**
 * Associative array / hash map.
 * Params:
 *     K = the key type
 *     V = the value type
 *     Allocator = the allocator type to use. Defaults to `Mallocator`
 *     hashFunction = the hash function to use on the keys
 *     supportGC = true if the container should support holding references to
 *         GC-allocated memory.
 */
struct HashMap(K, V, Allocator = Mallocator, alias hashFunction = generateHash!K,
	bool supportGC = shouldAddGCRange!K || shouldAddGCRange!V)
{
	this(this) @disable;

	private import std.experimental.allocator.common : stateSize;

	static if (stateSize!Allocator != 0)
	{
		this() @disable;

		/**
		 * Use the given `allocator` for allocations.
		 */
		this(Allocator allocator)
		in
		{
			assert(allocator !is null, "Allocator must not be null");
		}
		body
		{
			this.allocator = allocator;
		}

		/**
		 * Constructs an HashMap with an initial bucket count of bucketCount. bucketCount
		 * must be a power of two.
		 */
		this(size_t bucketCount, Allocator allocator)
		in
		{
			assert(allocator !is null, "Allocator must not be null");
			assert((bucketCount & (bucketCount - 1)) == 0, "bucketCount must be a power of two");
		}
		body
		{
			this.allocator = allocator;
			initialize(bucketCount);
		}

		invariant
		{
			assert(allocator !is null);
		}
	}
	else
	{
		/**
		 * Constructs an HashMap with an initial bucket count of bucketCount. bucketCount
		 * must be a power of two.
		 */
		this(size_t bucketCount)
		in
		{
			assert((bucketCount & (bucketCount - 1)) == 0, "bucketCount must be a power of two");
		}
		body
		{
			initialize(bucketCount);
		}
	}

	~this()
	{
		import std.experimental.allocator : dispose;
		static if (useGC)
			GC.removeRange(buckets.ptr);
		allocator.dispose(buckets);
	}

	/**
	 * Supports $(B aa[key]) syntax.
	 */
	auto opIndex(this This)(K key)
	{
		import std.conv : text;

		alias CET = ContainerElementType!(This, V);

		if (buckets.length == 0)
			throw new Exception("'" ~ text(key) ~ "' not found in HashMap");
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (ref r; buckets[index].range)
		{
			static if (storeHash)
			{
				if (r.hash == hash && r == key)
					return cast(CET) r.value;
			}
			else
			{
				if (r == key)
					return cast(CET) r.value;
			}
		}
		throw new Exception("'" ~ text(key) ~ "' not found in HashMap");
	}

	/**
	 * Gets the value for the given key, or returns `defaultValue` if the given
	 * key is not present.
	 *
	 * Params:
	 *     key = the key to look up
	 *     value = the default value
	 * Returns: the value indexed by `key`, if present, or `defaultValue` otherwise.
	 */
	auto get(this This)(K key, lazy V defaultValue)
	{
		alias CET = ContainerElementType!(This, V);

		if (_length == 0)
			return defaultValue;
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (r; buckets[index].range)
		{
			static if (storeHash)
			{
				if (r.hash == hash && r == key)
					return cast(CET) r.value;
			}
			else
			{
				if (r == key)
					return cast(CET) r.value;
			}
		}
		return defaultValue;
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
	bool opBinaryRight(string op)(K key) const nothrow if (op == "in")
	{
		if (_length == 0)
			return false;
		size_t hash = generateHash(key);
		size_t index = hashToIndex(hash);
		foreach (ref node; buckets[index].range)
		{
			static if (storeHash)
			{
				if (node.hash == hash && node == key)
					return true;
			}
			else
			{
				if (node == key)
					return true;
			}
		}
		return false;
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
	 * Returns: the number of key/value pairs in this container.
	 */
	size_t length() const nothrow pure @property @safe @nogc
	{
		return _length;
	}

	/**
	 * Returns: `true` if there are no items in this container.
	 */
	bool empty() const nothrow pure @property @safe @nogc
	{
		return _length == 0;
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
	auto values(this This)() const @property
	out(result)
	{
		assert (result.length == _length);
	}
	body
	{
		import std.array : appender;
		auto app = appender!(ContainerElementType!(This, V)[])();
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
	int opApply(D)(D del) if(isOpApplyDelegate!(D, const K, V))
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

	///
	int opApply(D)(D del) const if(isOpApplyDelegate!(D, const K, const V))
	{
		int result = 0;
		foreach (const ref bucket; buckets)
		{
			foreach (const ref node; bucket.range)
			{
				result = del(node.key, node.value);
				if (result != 0)
					return result;
			}
		}
		return result;
	}

private:

	import std.experimental.allocator : make;
	import std.traits : isBasicType;
	import containers.unrolledlist : UnrolledList;
	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;
	import containers.internal.mixins : AllocatorState;
	import core.memory : GC;

	enum bool storeHash = !isBasicType!K;
	enum bool useGC = supportGC && (shouldAddGCRange!K || shouldAddGCRange!V);

	template isOpApplyDelegate(D, KT, VT)
	{
		import std.traits : isDelegate, isImplicitlyConvertible, isIntegral, Parameters, ReturnType;

		enum isOpApplyDelegate = isDelegate!D
			&& isIntegral!(ReturnType!D)
			&& Parameters!(D).length == 2
			&& is(KT == Parameters!(D)[0])
			&& isImplicitlyConvertible!(VT, Parameters!(D)[1]);
	}

	void initialize(size_t bucketCount = 4)
	{
		import std.conv : emplace;

		buckets = (cast(Bucket*) allocator.allocate(bucketCount * Bucket.sizeof))[0 .. bucketCount];
		static if (useGC)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		foreach (ref bucket; buckets)
		{
			static if (stateSize!Allocator == 0)
				emplace(&bucket);
			else
				emplace(&bucket, allocator);
		}
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
//		import std.experimental.allocator : make, dispose;
		import std.conv : emplace;
		immutable size_t newLength = buckets.length << 1;
		immutable size_t newSize = newLength * Bucket.sizeof;
		Bucket[] oldBuckets = buckets;
		assert (oldBuckets.ptr == buckets.ptr);
		buckets = cast(Bucket[]) allocator.allocate(newSize);
		static if (useGC)
			GC.addRange(buckets.ptr, buckets.length * Bucket.sizeof);
		assert (buckets);
		assert (buckets.length == newLength);
		foreach (ref bucket; buckets)
		{
			static if (stateSize!Allocator == 0)
				emplace(&bucket);
			else
				emplace(&bucket, allocator);
		}

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
		static if (useGC)
			GC.removeRange(oldBuckets.ptr);
		allocator.deallocate(cast(void[]) oldBuckets);
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
		ContainerStorageType!K key;
		ContainerStorageType!V value;
	}

	mixin AllocatorState!Allocator;
	alias Bucket = UnrolledList!(Node, Allocator, useGC);
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
	foreach (const ref string k, ref int v; hm) {}

	auto hm2 = HashMap!(char, char)(4);
	hm2['a'] = 'a';

	HashMap!(int, int) hm3;
	assert (hm3.get(100, 20) == 20);
	hm3[100] = 1;
	assert (hm3.get(100, 20) == 1);
}

unittest
{
    static class Foo
    {
        string name;
    }

    void someFunc(ref in HashMap!(string,Foo) map) @safe
    {
		static assert(is(typeof(map[""]) == const(Foo)));
        foreach (const ref string k, const ref Foo v; map)
        {
            assert (k == "foo");
            assert (v.name == "Foo");
        }
    }

    void someFunc2(ref HashMap!(string,Foo) map) @safe
    {
		static assert(is(typeof(map[""]) == Foo));
        foreach (const ref string k, Foo v; map)
        {
            assert (k == "foo");
            assert (v.name == "Foo");
        }
    }

    auto hm = HashMap!(string, Foo)(16);
    auto f = new Foo;
    f.name = "Foo";
    hm.insert("foo", f);
    assert("foo" in hm);
    someFunc(hm);
    someFunc2(hm);
}

unittest
{
    HashMap!(string, int) map;
    map.insert("foo", 0);
    map.insert("bar", 0);

    foreach(const(string) key, ref int value; map) {
        value = 1;
    }

    foreach(const(string) key, ref int value; map) {
        assert(value == 1);
    }
}

unittest
{
    HashMap!(string, int) map;
    map.insert("foo", 0);
    map.insert("bar", 0);

    foreach(key; map.keys()) {
        map[key] = 1;
    }

    foreach(const(string) key, ref int value; map) {
        assert(value == 1);
    }
}
