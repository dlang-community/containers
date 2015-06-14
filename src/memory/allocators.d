/**
 * (Hopefully) useful _allocators.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module memory.allocators;

import std.experimental.allocator;
import std.experimental.allocator.free_list;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.bitmapped_block;

/**
 * Allocator used for allocating nodes of a fixed size.
 */
template NodeAllocator(size_t nodeSize, size_t blockSize = 1024)
{
	private size_t roundUpToMultipleOf(size_t s, uint base) pure nothrow @safe
	{
		assert(base);
		auto rem = s % base;
		return rem ? s + base - rem : s;
	}

	enum ns = roundUpToMultipleOf(
		nodeSize >= (void*).sizeof ? nodeSize : (void*).sizeof, (void*).sizeof);
	static assert (ns <= BitmappedBlock!(blockSize, platformAlignment, Mallocator).maxAllocationSize);
	alias NodeAllocator = FreeList!(BlockAllocator!blockSize, ns);
}

///
unittest
{
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

/**
 * Allocator that performs most small allocations on the stack, then falls over
 * to malloc/free when necessary.
 */
template QuickAllocator(size_t stackCapacity)
{
	alias QuickAllocator = FallbackAllocator!(InSituRegion!stackCapacity, Mallocator);
}

///
unittest
{
	QuickAllocator!1024 quick;
	void[] mem = quick.allocate(1_000);
	assert (mem);
	quick.deallocate(mem);
	mem = quick.allocate(10_000);
	assert (mem);
	quick.deallocate(mem);
}
