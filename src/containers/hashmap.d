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
	bool supportGC = shouldAddGCRange!K || shouldAddGCRange!V,
	bool storeHash = !isBasicType!K)
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

		static if (useGC)
			GC.removeRange(buckets.ptr);
		allocator.dispose(buckets);
		buckets = null;
		_length = 0;
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
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (r; buckets[index])
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
	 * Returns: `true` if there is an entry in this map for the given `key`,
	 *     false otherwise.
	 */
	bool containsKey(this This)(K key) inout pure @nogc @safe
	{
		if (buckets.length == 0)
			return false;
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (r; buckets[index])
		{
			static if (storeHash)
			{
				if (r.hash == hash && r.key == key)
					return true;
			}
			else
			{
				if (r.key == key)
					return true;
			}
		}
		return false;
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
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (r; buckets[index])
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

		if (buckets.length == 0)
			initialize();
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (ref item; buckets[index])
		{
			static if (storeHash)
			{
				if (item.hash == hash && item.key == key)
					return cast(CET*)&item.value;
			}
			else
			{
				if (item.key == key)
					return cast(CET*)&item.value;
			}
		}
		Node* n;
		static if (storeHash)
			n = buckets[index].put(Node(hash, key, defaultValue));
		else
			n = buckets[index].put(Node(key, defaultValue));
		_length++;
		if (shouldRehash)
		{
			rehash();
			return key in this;
		}
		else
			return &n.value;
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
	inout(V)* opBinaryRight(string op)(K key) inout nothrow @trusted if (op == "in")
	{
		if (_length == 0)
			return null;
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (ref node; buckets[index])
		{
			static if (storeHash)
			{
				if (node.hash == hash && node == key)
					return &(cast(inout)node).value;
			}
			else
			{
				if (node == key)
					return &(cast(inout)node).value;
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
		Hash hash = hashFunction(key);
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
		if (buckets.length == 0)
			initialize();
		Hash hash = hashFunction(key);
		size_t index = hashToIndex(hash);
		foreach (ref item; buckets[index])
		{
			static if (storeHash)
			{
				if (item.hash == hash && item.key == key)
				{
					item.value = value;
					return &item;
				}
			}
			else
			{
				if (item.key == key)
				{
					item.value = value;
					return &item;
				}
			}
		}
		Node* n;
		static if (storeHash)
			n = buckets[index].insertAnywhere(Node(hash, key, value));
		else
			n = buckets[index].insertAnywhere(Node(key, value));
		_length++;
		if (shouldRehash)
			rehash();
		return n;
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
			{
				static if (storeHash)
				{
					size_t index = hashToIndex(node.hash);
					buckets[index].put(Node(node.hash, node.key, node.value));
				}
				else
				{
					Hash hash = hashFunction(node.key);
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

	size_t hashIndex(K key) const
	out (result)
	{
		assert (result < buckets.length);
	}
	body
	{
		return hashToIndex(hashFunction(key));
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
			Hash hash;
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

unittest
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
unittest
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

unittest
{
	HashMap!(int, int) map;
	auto p = map.getOrAdd(1, 1);
	assert(*p == 1);
	*p = 2;
	assert(map[1] == 2);
}
