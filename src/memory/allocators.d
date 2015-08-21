/**
 * (Hopefully) useful _allocators.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module memory.allocators;


/**
 * Allocator used for allocating nodes of a fixed size.
 */
template NodeAllocator(size_t nodeSize, size_t blockSize = 1024)
{
	import std.experimental.allocator.building_blocks.allocator_list : AllocatorList;
	import std.experimental.allocator.building_blocks.free_list : FreeList;
	import std.experimental.allocator.mallocator : Mallocator;
	import std.experimental.allocator.building_blocks.region : Region;

	private size_t roundUpToMultipleOf(size_t s, uint base) pure nothrow @safe
	{
		assert(base);
		auto rem = s % base;
		return rem ? s + base - rem : s;
	}

	enum ns = roundUpToMultipleOf(
		nodeSize >= (void*).sizeof ? nodeSize : (void*).sizeof, (void*).sizeof);
	alias NodeAllocator = FreeList!(AllocatorList!(n => Region!Mallocator(blockSize)), ns);
}

///
unittest
{
	import std.experimental.allocator : make, dispose;

	enum testSize = 4_000;
	static struct Node { Node* next; int payload; }
	NodeAllocator!(Node.sizeof, 2048) nodeAllocator;
	Node*[testSize] nodes;
	foreach (i; 0 .. testSize)
		nodes[i] = nodeAllocator.make!Node();
	foreach (i; 0 .. testSize)
		assert (nodes[i] !is null);
	foreach (i; 0 .. testSize)
		nodeAllocator.dispose(nodes[i]);
}
