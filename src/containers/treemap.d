/**
 * Tree Map
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.treemap;

private import containers.internal.node : shouldAddGCRange;
private import std.experimental.allocator.mallocator : Mallocator;

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

	private import std.experimental.allocator.common : stateSize;

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

	/**
	 * Inserts the given key-value pair.
	 */
	void insert(V value, K key)
	{
		auto tme = TreeMapElement(key, value);
		tree.insert(tme);
	}

	/// Supports $(B treeMap[key] = value;) syntax.
	alias opIndexAssign = insert;

	/// Supports $(B treeMap[key]) syntax.
	auto opIndex(this This)(K key) const
	{
		alias CET = ContainerElementType!(This, V);
		auto tme = TreeMapElement(key);
		return cast(CET) tree.equalRange(tme).front.value;
	}

	/**
	 * Removes the key→value mapping for the given key.
	 * Params: key = the key to remove
	 * Returns: true if the key existed in the map
	 */
	bool remove(K key)
	{
		auto tme = TreeMapElement(key);
		return tree.remove(tme);
	}

	/// Returns: true if the mapping contains the given key
	bool containsKey(K key)
	{
		auto tme = TreeMapElement(key);
		return tree.contains(tme);
	}

	/// Returns: true if the mapping is empty
	bool empty() const pure nothrow @property @safe @nogc
	{
		return tree.empty;
	}

	/// Returns: the number of key→value pairs in the map
	size_t length() const pure nothrow @property @safe @nogc
	{
		return tree.length;
	}

	auto keys() const pure nothrow @property @safe @nogc
	{
		import std.algorithm.iteration : map;
		return tree[].map!(a => a.key);
	}

	auto values() const pure nothrow @property @safe @nogc
	{
		import std.algorithm.iteration : map;
		return tree[].map!(a => a.value);
	}

	/// Supports $(B foreach(k, v; treeMap)) syntax.
	int opApply(this This)(int delegate(ref K, ref V) loopBody)
	{
		int result;
		foreach (ref tme; tree[])
		{
			result = loopBody(tme.key, tme.value);
			if (result)
				break;
		}
		return result;
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
	static if (stateSize!Allocator == 0)
		TreeType tree = void;
	else
		TreeType tree;
}

version (EmsiContainersUnittest):

unittest
{
	TreeMap!(string, string) tm;
	tm["test1"] = "hello";
	tm["test2"] = "world";
	tm.remove("test1");
	tm.remove("test2");
}

unittest
{
	import std.experimental.allocator.building_blocks.free_list : FreeList;
	import std.experimental.allocator.building_blocks.allocator_list : AllocatorList;
	import std.experimental.allocator.building_blocks.region : Region;
	import std.experimental.allocator.building_blocks.stats_collector : StatsCollector;
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
