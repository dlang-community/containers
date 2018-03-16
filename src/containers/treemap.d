/**
 * Tree Map
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.treemap;

private import containers.internal.node : shouldAddGCRange;
private import stdx.allocator.mallocator : Mallocator;

/**
 * A key→value mapping where the keys are guaranteed to be sorted.
 * Params:
 *     K = the key type
 *     V = the value type
 *     Allocator = the allocator to use. Defaults to `Mallocator`.
 *     less = the key comparison function to use
 *     supportGC = true to support storing GC-allocated objects, false otherwise
 *     cacheLineSize = the size of the internal nodes in bytes
 */
struct TreeMap(K, V, Allocator = Mallocator, alias less = "a < b",
	bool supportGC = shouldAddGCRange!K || shouldAddGCRange!V, size_t cacheLineSize = 64)
{
	this(this) @disable;

	private import stdx.allocator.common : stateSize;

	static if (stateSize!Allocator != 0)
	{
		/// No default construction if an allocator must be provided.
		this() @disable;

		/**
		 * Use the given `allocator` for allocations.
		 */
		this(Allocator allocator)
		{
			tree = TreeType(allocator);
		}
	}

    void clear()
    {
        tree.clear();
    }

	/**
	 * Inserts or overwrites the given key-value pair.
	 */
	void insert(K key, V value) @safe
	{
		auto tme = TreeMapElement(key, value);
		tree.insert(tme, true);
	}

	/// Supports $(B treeMap[key] = value;) syntax.
	void opIndexAssign(V value, K key)
    {
        insert(key, value);
    }

	/**
	 * Supports $(B treeMap[key]) syntax.
	 *
	 * Throws: RangeError if the key does not exist.
	 */
	auto opIndex(this This)(K key) inout
	{
		alias CET = ContainerElementType!(This, V);
		auto tme = TreeMapElement(key);
		return cast(CET) tree.equalRange(tme).front.value;
	}

    /**
     * Returns: the value associated with the given key, or the given `defaultValue`.
     */
    auto get(this This)(K key, lazy V defaultValue) inout @trusted
    {
        alias CET = ContainerElementType!(This, V);
		auto tme = TreeMapElement(key);
        auto er = tree.equalRange(tme);
        if (er.empty)
            return cast(CET) defaultValue;
        else
            return cast(CET) er.front.value;
    }

    /**
	 * If the given key does not exist in the TreeMap, adds it with
	 * the value `defaultValue`.
	 *
	 * Params:
	 *     key = the key to look up
	 *     value = the default value
	 */
    auto getOrAdd(this This)(K key, lazy V value) @safe
    {
        alias CET = ContainerElementType!(This, V);
		auto tme = TreeMapElement(key);
        auto er = tree.equalRange(tme);
        if (er.empty)
        {
            insert(value, key);
            return value;
        }
        else
            return er.front.value;
    }

	/**
	 * Removes the key→value mapping for the given key.
     *
	 * Params: key = the key to remove
	 * Returns: true if the key existed in the map
	 */
	bool remove(K key)
	{
		auto tme = TreeMapElement(key);
		return tree.remove(tme);
	}

	/**
	 * Returns: true if the mapping contains the given key
	 */
	bool containsKey(K key) inout pure nothrow @nogc @safe
	{
		auto tme = TreeMapElement(key);
		return tree.contains(tme);
	}

	/**
	 * Returns: true if the mapping is empty
	 */
	bool empty() const pure nothrow @property @safe @nogc
	{
		return tree.empty;
	}

	/**
	 * Returns: the number of key→value pairs in the map
	 */
	size_t length() inout pure nothrow @property @safe @nogc
	{
		return tree.length;
	}

	/**
	 * Returns: a GC-allocated array of the keys in the map
	 */
	auto keys(this This)() inout pure @property @trusted
	{
		import std.array : array;

		return byKey!(This)().array();
	}

	/**
	 * Returns: a range of the keys in the map
	 */
	auto byKey(this This)() inout pure @trusted
	{
		import std.algorithm.iteration : map;
		alias CETK = ContainerElementType!(This, K);

		return tree[].map!(a => cast(CETK) a.key);
	}

	/**
	 * Returns: a GC-allocated array of the values in the map
	 */
	auto values(this This)() inout pure @property @trusted
	{
		import std.array : array;

		return byValue!(This)().array();
	}

	/**
	 * Returns: a range of the values in the map
	 */
	auto byValue(this This)() inout pure @trusted
	{
		import std.algorithm.iteration : map;
		alias CETV = ContainerElementType!(This, V);

		return tree[].map!(a => cast(CETV) a.value);
	}

	/// ditto
	alias opSlice = byValue;

	/**
	 * Returns: a range of the kev/value pairs in this map. The element type of
	 *     this range is a struct with `key` and `value` fields.
	 */
	auto byKeyValue() inout pure @safe
	{
		return tree[];
	}

private:

	import containers.ttree : TTree;
	import containers.internal.storage_type : ContainerStorageType;
	import containers.internal.element_type : ContainerElementType;

	enum bool useGC = supportGC && (shouldAddGCRange!K || shouldAddGCRange!V);

	static struct TreeMapElement
	{
		ContainerStorageType!K key;
		ContainerStorageType!V value;
		int opCmp(ref const TreeMapElement other) const
		{
			import std.functional : binaryFun;
			return binaryFun!less(key, other.key);
		}
	}

	alias TreeType = TTree!(TreeMapElement, Allocator, false, "a.opCmp(b) > 0", useGC, cacheLineSize);
    TreeType tree;
}

@system unittest
{
	TreeMap!(string, string) tm;
	tm["test1"] = "hello";
	tm["test2"] = "world";
    assert(tm.get("test1", "something") == "hello");
	tm.remove("test1");
	tm.remove("test2");
    assert(tm.length == 0);
    assert(tm.empty);
    assert(tm.get("test4", "something") == "something");
    assert(tm.get("test4", "something") == "something");
}

unittest
{
	import stdx.allocator.building_blocks.free_list : FreeList;
	import stdx.allocator.building_blocks.allocator_list : AllocatorList;
	import stdx.allocator.building_blocks.region : Region;
	import stdx.allocator.building_blocks.stats_collector : StatsCollector;
	import std.stdio : stdout;
	import std.algorithm.iteration : walkLength;

	StatsCollector!(FreeList!(AllocatorList!(a => Region!(Mallocator)(1024 * 1024)),
		64)) allocator;
	{
		auto intMap = TreeMap!(int, int, typeof(&allocator))(&allocator);
		foreach (i; 0 .. 10_000)
			intMap[i] = 10_000 - i;
		assert(intMap.length == 10_000);
	}
	assert(allocator.numAllocate == allocator.numDeallocate);
	assert(allocator.bytesUsed == 0);
}

unittest
{
	import std.algorithm.iteration : each;
	import std.algorithm.comparison : equal;
	import std.range : repeat, take;

	TreeMap!(int, int) tm;
	int[] a = [1, 2, 3, 4, 5];
	a.each!(a => tm[a] = 0);
	assert(equal(tm.keys, a));
	assert(equal(tm.values, repeat(0).take(a.length)));
}

unittest
{
    static class Foo
    {
        string name;
    }

    TreeMap!(string, Foo) tm;
    auto f = new Foo;
    tm["foo"] = f;
}
