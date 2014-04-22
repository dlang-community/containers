/**
 * (Hopefully) useful _allocators.
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */

module memory.allocators;

import std.allocator;

/**
 * Allocator used for allocating nodes of a fixed size.
 */
template NodeAllocator(size_t nodeSize, size_t blockSize = 1024)
{
	enum ns = roundUpToMultipleOf(
		nodeSize >= (void*).sizeof ? nodeSize : (void*).sizeof, (void*).sizeof);
	static assert (ns <= BlockAllocator!(blockSize).maxAllocationSize);
	alias NodeAllocator = Freelist!(BlockAllocator!(blockSize), ns, ns);
}

///
unittest
{
	enum testSize = 4_000;
	static struct Node { Node* next; int payload; }
	NodeAllocator!(Node.sizeof, 2048) nodeAllocator;
	Node*[testSize] nodes;
	foreach (i; 0 .. testSize)
		nodes[i] = allocate!Node(nodeAllocator);
	foreach (i; 0 .. testSize)
		assert (nodes[i] !is null);
	foreach (i; 0 .. testSize)
		deallocate(nodeAllocator, nodes[i]);
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

/**
 * Simple allocator that allocates memory in chucks of blockSize, and then frees
 * all of its blocks when it goes out of scope. The block allocator is reference
 * counted, so it may be copied safely. It does not support freeing any
 * memory allocated by it. Deallocation only occurs by destroying the entire
 * allocator. Note that it is not possible to allocate blockSize bytes with this
 * allocator due to some memory being used for internal record keeping.
 */
struct BlockAllocator(size_t blockSize)
{
	/**
	 * Frees all memory allocated by this allocator
	 */
	~this() pure nothrow @trusted
	{
		if (--refCount > 0)
			return;
		Node* current = root;
		Node* previous = void;
		uint i = 0;
		while (current !is null)
		{
			previous = current;
			current = current.next;
			assert (previous == previous.memory.ptr);
			Mallocator.it.deallocate(previous.memory);
			i++;
		}
		root = null;
	}

	/**
	 * Standard allocator operation.
	 */
	void[] allocate(size_t bytes) pure nothrow @trusted
	in
	{
		import std.string;
		assert (bytes <= maxAllocationSize, format("Cannot allocate %d bytes"
			~ " from an allocator with block size of %d and max allocation"
			~ " size of %d", bytes, blockSize, maxAllocationSize));
	}
	out (result)
	{
		import std.string;
		assert (result.length == bytes, format("Allocated %d bytes when %d"
			~ " bytes were requested.", result.length, bytes));
	}
	body
	{
		// Allocate from the beginning of the list. Filled blocks go later in
		// the list.
		// Give up after three blocks. We don't want to do a full linear scan.
		size_t i = 0;
		for (Node* current = root; current !is null && i < 3; current = current.next)
		{
			void[] mem = allocateInNode(current, bytes);
			if (mem !is null)
				return mem;
			i++;
		}
		Node* n = allocateNewNode();
		void[] mem = allocateInNode(n, bytes);
		n.next = root;
		root = n;
		return mem;
	}

	/**
	 * The maximum number of bytes that can be allocated at a time with this
	 * allocator. This is smaller than blockSize because of some internal
	 * bookkeeping information.
	 */
	enum maxAllocationSize = blockSize - Node.sizeof;

	/**
	 * Allocator's memory alignment
	 */
	enum alignment = platformAlignment;

private:

	/**
	 * Allocates a new node along with its memory
	 */
	Node* allocateNewNode() pure nothrow const @trusted
	{
		void[] memory = Mallocator.it.allocate(blockSize);
		Node* n = cast(Node*) memory.ptr;
		n.used = roundUpToMultipleOf(Node.sizeof, platformAlignment);
		n.memory = memory;
		n.next = null;
		return n;
	}

	/**
	 * Allocates memory from the given node
	 */
	void[] allocateInNode(Node* node, size_t bytes) pure nothrow const @safe
	in
	{
		assert (node !is null);
	}
	body
	{
		if (node.used + bytes > node.memory.length)
			return null;
		immutable prev = node.used;
		node.used = roundUpToMultipleOf(node.used + bytes, platformAlignment);
		return node.memory[prev .. prev + bytes];
	}

	/**
	 * Single linked list of allocated blocks
	 */
	static struct Node
	{
		void[] memory;
		size_t used;
		Node* next;
	}

	/**
	 * Pointer to the first item in the node list
	 */
	Node* root;

	/**
	 * Reference count
	 */
	uint refCount = 1;

	/**
	 * Returns s rounded up to a multiple of base.
	 */
	static size_t roundUpToMultipleOf(size_t s, uint base) pure nothrow @safe
	{
		assert(base);
		auto rem = s % base;
		return rem ? s + base - rem : s;
	}
}

unittest
{
	BlockAllocator!(1024 * 4 * 10) blockAllocator;
	void[] mem = blockAllocator.allocate(10);
	assert (mem);
	void[] mem2 = blockAllocator.allocate(10_000);
	assert (mem2);
}

private size_t roundUpToMultipleOf(size_t s, uint base) pure nothrow @safe
{
	assert(base);
	auto rem = s % base;
	return rem ? s + base - rem : s;
}
