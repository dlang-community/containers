/**
 * Tree Map
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.treemap;

/**
 * A key→value mapping where the keys are guaranteed to be sorted.
 * Params:
 *     K = the key type
 *     V = the value type
 *     less = the key comparison function to use
 *     supportGC = true to support storing GC-allocated objects, false otherwise
 *     cacheLineSize = the size of the internal nodes in bytes
 */
struct TreeMap(K, V, alias less = "a < b", bool supportGC = true,
	size_t cacheLineSize = 64)
{

	this(this) @disable;

	/// Supports $(B treeMap[key] = value;) syntax.
	void opIndexAssign(V value, K key)
	{
		auto tme = TreeMapElement(key, value);
		tree.insert(tme);
	}

	/// Supports $(B treeMap[key]) syntax.
	V opIndex(K key) const
	{
		auto tme = TreeMapElement(key);
		return tree.equalRange(tme).front.value;
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
	bool empty() const pure nothrow @property
	{
		return tree.empty;
	}

	/// Returns: the number of key→value pairs in the map
	size_t length() const pure nothrow @property
	{
		return tree.length;
	}

	/// Supports $(B foreach(k, v; treeMap)) syntax.
	int opApply(int delegate(ref K, ref V) loopBody)
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

	import containers.ttree;

	static struct TreeMapElement
	{
		K key;
		V value;
		int opCmp(ref const TreeMapElement other) const
		{
			import std.functional;
			return binaryFun!less(key, other.key);
		}
	}
	TTree!(TreeMapElement, false, "a.opCmp(b) > 0", supportGC, cacheLineSize) tree;
}
