/**
 * Hash Map
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.hashmap;

private import containers.internal.hash : generateHash;
private import containers.internal.node : shouldAddGCRange;
private import stdx.allocator.mallocator : Mallocator;
private import std.traits : isBasicType, Unqual;

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

	private import stdx.allocator.common : stateSize;

	static if (stateSize!Allocator != 0)
	{
		this() @disable;

		/**
		 * Use the given `allocator` for allocations.
		 */
		this(Allocator allocator) pure nothrow @nogc @safe
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

	~this() nothrow
	{
		scope (failure) assert(false);
		clear();
	}

	/**
	 * Removes all items from the map
	 */
	void clear()
	{
		import stdx.allocator : dispose;

		// always remove ranges from GC first before disposing of buckets, to
		// prevent segfaults when the GC collects at an unfortunate time
		static if (useGC)
			GC.removeRange(buckets.ptr);
		allocator.dispose(buckets);

		buckets = null;
		_length = 0;
	}

	/**
	 * Supports `aa[key]` syntax.
	 */
	ref opIndex(this This)(K key)
	{
		import std.conv : text;
		import std.exception : enforce;

		alias CET = ContainerElementType!(This, V);
		size_t i;
		auto n = find(key, i);
		enforce(n !is null, "'" ~ text(key) ~ "' not found in HashMap");
		return *cast(CET*) &n.value;
	}

	/**
	 * Returns: `true` if there is an entry in this map for the given `key`,
	 *     false otherwise.
	 */
	bool containsKey(this This)(K key) inout pure @nogc @safe
	{
		return find(key) !is null;
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

		size_t i;
		auto n = find(key, i);
		if (n is null)
			return defaultValue;
		return cast(CET) n.value;
	}

	/**
	 * If the given key does not exist in the HashMap, adds it with
	 * the value `defaultValue`.
	 *
	 * Params:
	 *     key = the key to look up
	 *     value = the default value
	 * Returns: a pointer to the value stored in the HashMap with the given key.
	 *     The pointer is guaranteed to be valid only until the next HashMap
	 *     modification.
	 */
	auto getOrAdd(this This)(K key, lazy V defaultValue)
	{
		alias CET = ContainerElementType!(This, V);

		Hash hash = hashFunction(key);
		auto n = find(key, hash);
		if (n is null)
			return cast(CET*) &insert(key, defaultValue).value;
		else
			return cast(CET*) &n.value;
	}

	/**
	 * Supports $(B aa[key] = value;) syntax.
	 */
	void opIndexAssign(V value, const K key)
	{
		insert(key, value);
	}

	/**
	 * Supports $(B key in aa) syntax.
	 *
	 * Returns: pointer to the value corresponding to the given key,
	 * or null if the key is not present in the HashMap.
	 */
	inout(V)* opBinaryRight(string op)(const K key) inout nothrow @trusted if (op == "in")
	{
		size_t i;
		auto n = find(key, i);
		if (n is null)
			return null;
		return &(cast(inout) n).value;
	}

	/**
	 * Removes the value associated with the given key
	 * Returns: true if a value was actually removed.
	 */
	bool remove(K key)
	{
		size_t i;
		auto n = find(key, i);
		if (n is null)
			return false;
		immutable bool removed = buckets[i].remove(Node(n.hash, n.key));
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
	 * Returns: a range of the keys in this map.
	 */
	auto byKey(this This)() inout @trusted
	{
		return MapRange!(This, IterType.key)(cast(Unqual!(This)*) &this);
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
			foreach (item; bucket)
				app.put(item.key);
		}
		return app.data;
	}


	/**
	 * Returns: a range of the values in this map.
	 */
	auto byValue(this This)() inout @trusted
	{
		return MapRange!(This, IterType.value)(cast(Unqual!(This)*) &this);
	}

	/// ditto
	alias opSlice = byValue;

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
			foreach (item; bucket)
				app.put(cast(ContainerElementType!(This, V)) item.value);
		}
		return app.data;
	}

	/**
	 * Returns: a range of the kev/value pairs in this map. The element type of
	 *     this range is a struct with `key` and `value` fields.
	 */
	auto byKeyValue(this This)() inout @trusted
	{
		return MapRange!(This, IterType.both)(cast(Unqual!(This)*) &this);
	}

	mixin AllocatorState!Allocator;

private:

	import stdx.allocator : make, makeArray;
	import containers.unrolledlist : UnrolledList;
	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;
	import containers.internal.mixins : AllocatorState;
	import core.memory : GC;

	enum bool useGC = supportGC && (shouldAddGCRange!K || shouldAddGCRange!V);
	alias Hash = typeof({ K k = void; return hashFunction(k); }());

	enum IterType: ubyte
	{
		key, value, both
	}

	static struct MapRange(MapType, IterType Type)
	{
	static if (Type == IterType.both)
		{
			struct FrontType
			{
				ContainerElementType!(MapType, K) key;
				ContainerElementType!(MapType, V) value;
			}
		}
		else static if (Type == IterType.value)
			alias FrontType = ContainerElementType!(MapType, V);
		else static if (Type == IterType.key)
			alias FrontType = ContainerElementType!(MapType, K);
		else
			static assert(false);

		FrontType front()
		{
			static if (Type == IterType.both)
				return FrontType(cast(ContainerElementType!(MapType, K)) bucketRange.front.key,
					cast(ContainerElementType!(MapType, V)) bucketRange.front.value);
			else static if (Type == IterType.value)
				return cast(ContainerElementType!(MapType, V)) bucketRange.front.value;
			else static if (Type == IterType.key)
				return cast(ContainerElementType!(MapType, K)) bucketRange.front.key;
			else
				static assert(false);
		}

		bool empty() const pure nothrow @nogc @property
		{
			return _empty;
		}

		void popFront() pure nothrow @nogc
		{
			bucketRange.popFront();
			if (bucketRange.empty)
			{
				while (bucketRange.empty)
				{
					bucketIndex++;
					if (bucketIndex >= hm.buckets.length)
					{
						_empty = true;
						break;
					}
					else
						bucketRange = hm.buckets[bucketIndex][];
				}
			}
		}

	private:

		this(Unqual!(MapType)* hm)
		{
			this.hm = hm;
			this.bucketIndex = 0;
			bucketRange = typeof(bucketRange).init;
			this._empty = false;

			while (true)
			{
				if (bucketIndex >= hm.buckets.length)
				{
					_empty = true;
					break;
				}
				bucketRange = hm.buckets[bucketIndex][];
				if (bucketRange.empty)
					bucketIndex++;
				else
					break;
			}
		}

		Unqual!(MapType)* hm;
		size_t bucketIndex;
		typeof(hm.buckets[0].opSlice()) bucketRange;
		bool _empty;
	}

	void initialize(size_t bucketCount = 4)
	{
		import std.conv : emplace;
		assert((bucketCount & (bucketCount - 1)) == 0, "bucketCount must be a power of two");

		buckets = makeArray!Bucket(allocator, bucketCount);
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

	Node* insert(const K key, V value)
	{
		return insert(key, value, hashFunction(key));
	}

	Node* insert(const K key, V value, const Hash hash, const bool modifyLength = true)
	{
		if (buckets.length == 0)
			initialize();
		immutable size_t index = hashToIndex(hash);
		foreach (ref item; buckets[index])
		{
			if (item.hash == hash && item.key == key)
			{
				item.value = value;
				return &item;
			}
		}
		Node* n;
		n = buckets[index].insertAnywhere(Node(hash, key, value));
		if (modifyLength)
			_length++;
		if (shouldRehash())
			rehash();
		return n;
	}

	/**
	 * Returns: true if the load factor has been exceeded
	 */
	bool shouldRehash() const pure nothrow @safe @nogc
	{
		// We let this be greater than one because each bucket is an unrolled
		// list that has more than one element per linked list node.
		return (float(_length) / float(buckets.length)) > 1.33f;
	}

	/**
	 * Rehash the map.
	 */
	void rehash() @trusted
	{
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
			foreach (node; bucket)
				insert(node.key, node.value, node.hash, false);
			typeid(typeof(bucket)).destroy(&bucket);
		}
		static if (useGC)
			GC.removeRange(oldBuckets.ptr);
		allocator.deallocate(cast(void[]) oldBuckets);
	}

	size_t hashToIndex(Hash hash) const pure nothrow @safe @nogc
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
		return cast(size_t)hash & (buckets.length - 1);
	}

	inout(Node)* find(const K key, ref size_t index) inout
	{
		return find(key, index, hashFunction(key));
	}

	inout(Node)* find(const K key, ref size_t index, const Hash hash) inout
	{
		import std.array : empty;

		if (buckets.empty)
			return null;
		index = hashToIndex(hash);
		foreach (ref r; buckets[index])
		{
			if (r.hash == hash && r == key)
				return cast(inout(Node)*) &r;
		}
		return null;
	}

	struct Node
	{
		bool opEquals(ref const K key) const
		{
			return key == this.key;
		}

		bool opEquals(ref const Node n) const
		{
			return this.hash == n.hash && this.key == n.key;
		}

		Hash hash;
		ContainerStorageType!K key;
		ContainerStorageType!V value;
	}

	alias Bucket = UnrolledList!(Node, Allocator, useGC);
	Bucket[] buckets;
	size_t _length;
}

///
unittest
{
	import std.uuid : randomUUID;
	import std.algorithm.iteration : walkLength;

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
	hm["one"] = 2;
	assert(hm["one"] == 2);
	foreach (i; 0 .. 1000)
	{
		hm[randomUUID().toString] = i;
	}
	assert (hm.length == 1001);
	assert (hm.keys().length == hm.length);
	assert (hm.values().length == hm.length);
	() @nogc {
		assert (hm.byKey().walkLength == hm.length);
		assert (hm.byValue().walkLength == hm.length);
		assert (hm[].walkLength == hm.length);
		assert (hm.byKeyValue().walkLength == hm.length);
	}();
	foreach (v; hm) {}

	auto hm2 = HashMap!(char, char)(4);
	hm2['a'] = 'a';

	HashMap!(int, int) hm3;
	assert (hm3.get(100, 20) == 20);
	hm3[100] = 1;
	assert (hm3.get(100, 20) == 1);
	auto pValue = 100 in hm3;
	assert(*pValue == 1);
}

version(emsi_containers_unittest) unittest
{
	static class Foo
	{
		string name;
	}

	void someFunc(ref in HashMap!(string,Foo) map) @safe
	{
		foreach (kv; map.byKeyValue())
		{
			assert (kv.key == "foo");
			assert (kv.value.name == "Foo");
		}
	}

	auto hm = HashMap!(string, Foo)(16);
	auto f = new Foo;
	f.name = "Foo";
	hm.insert("foo", f);
	assert("foo" in hm);
}

// Issue #54
version(emsi_containers_unittest) unittest
{
	HashMap!(string, int) map;
	map.insert("foo", 0);
	map.insert("bar", 0);

	foreach (key; map.keys())
		map[key] = 1;
	foreach (key; map.byKey())
		map[key] = 1;

	foreach (value; map.byValue())
		assert(value == 1);
	foreach (value; map.values())
		assert(value == 1);
}

version(emsi_containers_unittest) unittest
{
	HashMap!(int, int) map;
	auto p = map.getOrAdd(1, 1);
	assert(*p == 1);
	*p = 2;
	assert(map[1] == 2);
}

debug (EMSI_CONTAINERS) version(emsi_containers_unittest) unittest
{
	import std.uuid : randomUUID;
	import std.algorithm.iteration : walkLength;
	import std.stdio;

	auto hm = HashMap!(string, int)(16);
	foreach (i; 0 .. 1_000_000)
	{
		auto str = randomUUID().toString;
		//writeln("Inserting ", str);
		hm[str] = i;
		//if (i > 0 && i % 100 == 0)
			//writeln(i);
	}
	writeln(hm.buckets.length);

	import std.algorithm.sorting:sort;
	ulong[ulong] counts;
	foreach (i, ref bucket; hm.buckets[])
		counts[bucket.length]++;
	foreach (k; counts.keys.sort())
		writeln(k, "=>", counts[k]);
}

// #74
version(emsi_containers_unittest) unittest
{
	HashMap!(string, size_t) aa;
	aa["b"] = 0;
	++aa["b"];
	assert(aa["b"] == 1);
}
