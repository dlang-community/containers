/**
 * Tree Map
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module containers.treemap;

struct TreeMap(K, V, alias less = "a < b", bool supportGC = true,
	size_t cacheLineSize = 64)
{

	this(this) @disable;

	void opIndexAssign(V value, K key)
	{
		auto tme = TreeMapElement(key, value);
		tree.insert(tme);
	}

	V opIndex(K key) const
	{
		auto tme = TreeMapElement(key);
		return tree.equalRange(tme).front.value;
	}

	bool remove(K key)
	{
		auto tme = TreeMapElement(key);
		return tree.remove(tme);
	}

	bool containsKey(K key)
	{
		auto tme = TreeMapElement(key);
		return tree.contains(tme);
	}

	bool empty() const pure nothrow @property
	{
		return tree.empty;
	}

	size_t length() const pure nothrow @property
	{
		return tree.length;
	}

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

	import containers.karytree;

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
	KAryTree!(TreeMapElement, false, "a.opCmp(b) > 0", supportGC, cacheLineSize) tree;
}
