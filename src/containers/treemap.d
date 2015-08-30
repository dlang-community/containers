/**
 * Tree Map
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module containers.treemap;

import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator.common : stateSize;

/**
 * A key→value mapping where the keys are guaranteed to be sorted.
 * Params:
 *     K = the key type
 *     V = the value type
 *     less = the key comparison function to use
 *     supportGC = true to support storing GC-allocated objects, false otherwise
 *     cacheLineSize = the size of the internal nodes in bytes
 */
struct TreeMap(K, V, Allocator = Mallocator, alias less = "a < b",
	bool supportGC = true, size_t cacheLineSize = 64)
{

	this(this) @disable;

	static if (stateSize!Allocator != 0)
	{
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

	alias TreeType = TTree!(TreeMapElement, Allocator, false, "a.opCmp(b) > 0", supportGC, cacheLineSize);
	static if (stateSize!Allocator == 0)
		TreeType tree = void;
	else
		TreeType tree;
}

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
	auto intMap = TreeMap!(int, int, typeof(&allocator))(&allocator);
	foreach (i; 0 .. 10_000)
		intMap[i] = 10_000 - i;
	assert(intMap.length == 10_000);
	destroy(intMap);
	assert(allocator.numAllocate == allocator.numDeallocate);
	assert(allocator.bytesUsed == 0);
}
