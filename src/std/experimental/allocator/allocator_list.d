module std.experimental.allocator.allocator_list;

import std.experimental.allocator.common;
import std.experimental.allocator.null_allocator;
import std.experimental.allocator.gc_allocator;
version(unittest) import std.stdio;

// Turn this on for debugging
// debug = allocator_list;

/**

Given an $(LUCKY object factory) of type `Factory` or a factory function
`factoryFunction`, and optionally also `BookkeepingAllocator` as a supplemental
allocator for bookkeeping, `AllocatorList` creates an allocator that lazily
creates as many allocators are needed for satisfying client allocation requests.

An embedded list builds a most-recently-used strategy: the most recent
allocators used in calls to either `allocate`, `owns` (successful calls
only), or `deallocate` are tried for new allocations in order of their most
recent use. Thus, although core operations take in theory $(BIGOH k) time for
$(D k) allocators in current use, in many workloads the factor is sublinear.
Details of the actual strategy may change in future releases.

`AllocatorList` is primarily intended for coarse-grained handling of
allocators, i.e. the number of allocators in the list is expected to be
relatively small compared to the number of allocations handled by each
allocator. However, the per-allocator overhead is small so using
`AllocatorList` with a large number of allocators should be satisfactory as long
as the most-recently-used strategy is fast enough for the application.

`AllocatorList` makes an effort to return allocated memory back when no
longer used. It does so by destroying empty allocators. However, in order to
avoid thrashing (excessive creation/destruction of allocators under certain use
patterns), it keeps unused allocators for a while.

Params:
factoryFunction = A function or template function (including function literals).
New allocators are created by calling `factoryFunction(n)` with strictly
positive numbers `n`. Delegates that capture their enviroment are not created
amid concerns regarding garbage creation for the environment. When the factory
needs state, a `Factory` object should be used.

BookkeepingAllocator = Allocator used for storing bookkeeping data. The size of
bookkeeping data is proportional to the number of allocators. If $(D
BookkeepingAllocator) is $(D NullAllocator), then $(D AllocatorList) is
"ouroboros-style", i.e. it keeps the bookkeeping data in memory obtained from
the allocators themselves. Note that for ouroboros-style management, the size
$(D n) passed to $(D make) will be occasionally different from the size
requested by client code.

Factory = Type of a factory object that returns new allocators on a need
basis. For an object $(D sweatshop) of type $(D Factory), `sweatshop(n)` should
return an allocator able to allocate at least `n` bytes (i.e. `Factory` must
define `opCall(size_t)` to return an allocator object). Usually the capacity of
allocators created should be much larger than $(D n) such that an allocator can
be used for many subsequent allocations. $(D n) is passed only to ensure the
minimum necessary for the next allocation. The factory object is allowed to hold
state, which will be stored inside `AllocatorList` as a direct `public` member
called `factory`.

*/
struct AllocatorList(Factory, BookkeepingAllocator = GCAllocator)
{
    import std.traits : hasMember;
    import std.conv : emplace;
    import std.algorithm : min, move;
    import std.experimental.allocator.stats_collector : StatsCollector, Options;

    private enum ouroboros = is(BookkeepingAllocator == NullAllocator);

    /**
    Alias for `typeof(Factory()(1))`, i.e. the type of the individual
    allocators.
    */
    alias Allocator = typeof(Factory.init(1));
    // Allocator used internally
    private alias SAllocator = StatsCollector!(Allocator, Options.bytesUsed);

    private static struct Node
    {
        // Allocator in this node
        SAllocator a;
        Node* next;

        @disable this(this);

        // Is this node unused?
        void setUnused() { next = &this; }
        bool unused() const { return next is &this; }

        // Just forward everything to the allocator
        alias a this;
    }

    /**
    If $(D BookkeepingAllocator) is not $(D NullAllocator), $(D bkalloc) is
    defined and accessible.
    */

    // State is stored in an array, but it has a list threaded through it by
    // means of "nextIdx".

    // state {
    static if (!ouroboros)
    {
        static if (stateSize!BookkeepingAllocator) BookkeepingAllocator bkalloc;
        else alias bkalloc = BookkeepingAllocator.it;
    }
    static if (stateSize!Factory)
    {
        Factory factory;
    }
    private Node[] allocators;
    private Node* root;
    // }

    static if (stateSize!Factory)
    {
        private auto makeAllocator(size_t n) { return factory(n); }
    }
    else
    {
        private auto makeAllocator(size_t n) { Factory f; return f(n); }
    }

    /**
    Constructs an `AllocatorList` given a factory object. This constructor is
    defined only if `Factory` has state.
    */
    static if (stateSize!Factory)
    this(ref Factory plant)
    {
        factory = plant;
    }
    /// Ditto
    static if (stateSize!Factory)
    this(Factory plant)
    {
        factory = plant;
    }

    static if (hasMember!(Allocator, "deallocateAll")
        && hasMember!(Allocator, "owns"))
    ~this()
    {
        deallocateAll();
    }

    /**
    The alignment offered.
    */
    enum uint alignment = Allocator.alignment;

    /**
    Allocate a block of size $(D s). First tries to allocate from the existing
    list of already-created allocators. If neither can satisfy the request,
    creates a new allocator by calling $(D make(s)) and delegates the request
    to it. However, if the allocation fresh off a newly created allocator
    fails, subsequent calls to $(D allocate) will not cause more calls to $(D
    make).
    */
    void[] allocate(size_t s)
    {
        Node* previous = null;
        Node* current = root;
        while (current !is null)
        {
            auto result = current.allocate(s);
            if (result.length == s)
            {
                assert(owns(result) == Ternary.yes);
                // Bring to front if not already
                if (root !is current)
                {
                    if (previous !is null)
                        previous.next = current.next;
                    current.next = root;
                    root = current;
                }
                return result;
            }
            else
            {
                previous = current;
                current = current.next;
            }
        }
        // Can't allocate from the current pool. Check if we just added a new
        // allocator, in that case it won't do any good to add yet another.
        if (root && root.empty == Ternary.yes)
        {
            // no can do
            return null;
        }
        // Add a new allocator
        if (auto a = addAllocator(s))
        {
            auto result = a.allocate(s);
            assert(result.ptr is null || owns(result) == Ternary.yes);
            return result;
        }
        return null;
    }

    private void moveAllocators(void[] newPlace)
    {
        assert(newPlace.ptr.alignedAt(Node.alignof));
        assert(newPlace.length % Node.sizeof == 0);
        auto newAllocators = cast(Node[]) newPlace;
        assert(allocators.length <= newAllocators.length);

        // Move allocators
        foreach (i, ref e; allocators)
        {
            if (e.unused)
            {
                newAllocators[i].setUnused;
                continue;
            }
            import core.stdc.string : memcpy;
            memcpy(&newAllocators[i].a, &e.a, e.a.sizeof);
            if (e.next)
            {
                newAllocators[i].next = newAllocators.ptr
                    + (e.next - allocators.ptr);
            }
            else
            {
                newAllocators[i].next = null;
            }
        }

        // Mark the unused portion as unused
        foreach (i; allocators.length .. newAllocators.length)
        {
            newAllocators[i].setUnused;
        }
        auto toFree = allocators;

        // Change state {
        root = newAllocators.ptr + (root - allocators.ptr);
        allocators = newAllocators;
        // }

        // Free the olden buffer
        static if (ouroboros)
        {
            static if (hasMember!(Allocator, "deallocate")
                    && hasMember!(Allocator, "owns"))
                deallocate(toFree);
        }
        else
        {
            bkalloc.deallocate(toFree);
        }
    }

    static if (ouroboros)
    private Node* addAllocator(size_t atLeastBytes)
    {
        void[] t = allocators;
        static if (hasMember!(Allocator, "expand")
            && hasMember!(Allocator, "owns"))
        {
            immutable bool expanded = t && this.expand(t, Node.sizeof);
        }
        else
        {
            enum expanded = false;
        }
        if (expanded)
        {
            import std.c.string : memcpy;
            assert(t.length % Node.sizeof == 0);
            assert(t.ptr.alignedAt(Node.alignof));
            allocators = cast(Node[]) t;
            allocators[$ - 1].setUnused;
            auto newAlloc = SAllocator(makeAllocator(atLeastBytes));
            memcpy(&allocators[$ - 1].a, &newAlloc, newAlloc.sizeof);
        }
        else
        {
            immutable toAlloc = (allocators.length + 1) * Node.sizeof
                + atLeastBytes + 128; // TODO: Why 128?
            auto newAlloc = SAllocator(makeAllocator(toAlloc));
            auto newPlace = newAlloc.allocate(
                (allocators.length + 1) * Node.sizeof);
            if (!newPlace) return null;
            moveAllocators(newPlace);
            import core.stdc.string : memcpy;
            memcpy(&allocators[$ - 1].a, &newAlloc, newAlloc.sizeof);
            assert(allocators[$ - 1].owns(allocators) == Ternary.yes);
        }
        // Insert as new root
        if (root != &allocators[$ - 1])
        {
            allocators[$ - 1].next = root;
            root = &allocators[$ - 1];
        }
        else
        {
            // This is the first one
            root.next = null;
        }
        assert(!root.unused);
        return root;
    }

    static if (!ouroboros)
    private Node* addAllocator(size_t atLeastBytes)
    {
        void[] t = allocators;
        if (bkalloc.expand(t, Node.sizeof))
        {
            assert(t.length % Node.sizeof == 0);
            assert(t.ptr.alignedAt(Node.alignof));
            allocators = cast(Node[]) t;
            allocators[$ - 1].setUnused;
        }
        else
        {
            // Could not expand, create a new block
            t = bkalloc.allocate((allocators.length + 1) * Node.sizeof);
            assert(t.length % Node.sizeof == 0);
            if (!t.ptr) return null;
            moveAllocators(t);
        }
        assert(allocators[$ - 1].unused);
        auto newAlloc = SAllocator(makeAllocator(atLeastBytes));
        import core.stdc.string : memcpy;
        memcpy(&allocators[$ - 1].a, &newAlloc, newAlloc.sizeof);
        emplace(&newAlloc);
        // Creation succeeded, insert as root
        allocators[$ - 1].next = root;
        root = &allocators[$ - 1];
        return root;
    }

    /**
    Defined only if $(D Allocator) defines $(D owns). Tries each allocator in
    turn, in most-recently-used order. If the owner is found, it is moved to
    the front of the list.
    */
    static if (hasMember!(Allocator, "owns"))
    Ternary owns(void[] b)
    {
        auto result = Ternary.no;
        for (Node* current = root; current !is null; current = current.next)
        {
            immutable t = current.owns(b);
            if (t != Ternary.yes)
            {
                if (t == Ternary.unknown) result = t;
                continue;
            }
            return Ternary.yes;
        }
        return result;
    }

    /**
    Defined only if $(D Allocator.expand) is defined. Finds the owner of $(D b)
    and calls $(D expand) for it. The owner is not brought to the head of the
    list.
    */
    static if (hasMember!(Allocator, "expand")
        && hasMember!(Allocator, "owns"))
    bool expand(ref void[] b, size_t delta)
    {
        if (!b.ptr)
        {
            b = allocate(delta);
            return b.length == delta;
        }
        for (Node* current = root; current !is null; current = current.next)
        {
            if (current.owns(b) == Ternary.yes) return current.expand(b, delta);
        }
        return false;
    }

    /**
    Defined only if $(D Allocator.reallocate) is defined. Finds the owner of
    $(D b) and calls $(D reallocate) for it. If that fails, calls the global
    $(D reallocate), which allocates a new block and moves memory.
    */
    static if (hasMember!(Allocator, "reallocate"))
    bool reallocate(ref void[] b, size_t s)
    {
        // First attempt to reallocate within the existing node
        if (!b.ptr)
        {
            b = allocate(s);
            return b.length == s;
        }
        for (Node* current = root; current !is null; current = current.next)
        {
            if (current.owns(b) == Ternary.yes) return current.reallocate(b, s);
        }
        // Failed, but we may find new memory in a new node.
        return .reallocate(this, b, s);
    }

    /**
     Defined if $(D Allocator.deallocate) and $(D Allocator.owns) are defined.
    */
    static if (hasMember!(Allocator, "deallocate")
        && hasMember!(Allocator, "owns"))
    bool deallocate(void[] b)
    {
        if (!b.ptr) return true;
        assert(allocators.length);
        assert(owns(b) == Ternary.yes);
        bool result;
        Node* current = root;
        Node* previous = null;
        while (current !is null)
        {
            if (current.owns(b) == Ternary.yes)
            {
                result = current.deallocate(b);
                // Bring to front
                if (root !is current)
                {
                    if (previous !is null)
                        previous.next = current.next;
                    current.next = root;
                    root = current;
                }
				return result;
            }
            previous = current;
            current = current.next;
        }
        // Hmmm... should we return this allocator back to the wild? Let's
        // decide if there are TWO empty allocators we can release ONE. This
        // is to avoid thrashing.
        // Note that loop starts from the second element.
        current = root.next;
        previous = null;
        if (current !is null && current.empty == Ternary.yes && current.next !is null)
        {
            while (current !is null)
            {
                if (!(current.unused || current.empty != Ternary.yes))
                {
                    // Used and empty baby, nuke it!
                    current.a.destroy();
                    if (previous !is null)
                        previous.next = current.next;
                    current.setUnused;
                    break;
                }
                previous = current;
                current = current.next;
            }
        }
        return result;
    }

    /**
    Defined only if $(D Allocator.owns) and $(D Allocator.deallocateAll) are
    defined.
    */
    static if (ouroboros && hasMember!(Allocator, "deallocateAll")
        && hasMember!(Allocator, "owns"))
    bool deallocateAll()
    {
        Node* special;
        foreach (ref n; allocators)
        {
            if (n.unused) continue;
            if (n.owns(allocators) == Ternary.yes)
            {
                special = &n;
                continue;
            }
            n.a.deallocateAll();
            n.a.destroy();
        }
        assert(special || !allocators.ptr);
        if (special !is null)
        {
            special.a.deallocateAll();
        }
        allocators = null;
        root = null;
        return true;
    }

    static if (!ouroboros && hasMember!(Allocator, "deallocateAll")
        && hasMember!(Allocator, "owns"))
    bool deallocateAll()
    {
        foreach (ref n; allocators)
        {
            if (n.unused) continue;
            n.a.deallocateAll;
            n.a.destroy;
        }
        static if (!is(BookkeepingAllocator == GCAllocator))
            bkalloc.deallocate(allocators);
        allocators = null;
        root = null;
        return true;
    }

    /// Returns $(D true) iff no allocators are currently active.
    Ternary empty() const
    {
        return Ternary(!allocators.length);
    }
}

/// Ditto
template AllocatorList(alias factoryFunction,
    BookkeepingAllocator = GCAllocator)
{
    alias A = typeof(factoryFunction(1));
    static assert(
        // is a template function (including literals)
        is(typeof({A function(size_t) @system x = factoryFunction!size_t;}))
        ||
        // or a function (including literals)
        is(typeof({A function(size_t) @system x = factoryFunction;}))
        ,
        "Only function names and function literals that take size_t"
            ~ " and return an allocator are accepted, not "
            ~ typeof(factoryFunction).stringof
    );
    static struct Factory
    {
        A opCall(size_t n) { return factoryFunction(n); }
    }
    alias AllocatorList = .AllocatorList!(Factory, BookkeepingAllocator);
}

///
version(Posix) unittest
{
    import std.algorithm : max;
    import std.experimental.allocator.region : Region;
    import std.experimental.allocator.mmap_allocator : MmapAllocator;
    import std.experimental.allocator.segregator : Segregator;
    import std.experimental.allocator.free_list : ContiguousFreeList;

    // Ouroboros allocator list based upon 4MB regions, fetched directly from
    // mmap. All memory is released upon destruction.
    alias A1 = AllocatorList!((n) => Region!MmapAllocator(max(n, 1024 * 4096)),
        NullAllocator);

    // Allocator list based upon 4MB regions, fetched from the garbage
    // collector. All memory is released upon destruction.
    alias A2 = AllocatorList!((n) => Region!GCAllocator(max(n, 1024 * 4096)));

    // Ouroboros allocator list based upon 4MB regions, fetched from the garbage
    // collector. Memory is left to the collector.
    alias A3 = AllocatorList!(
        (n) => Region!NullAllocator(new void[max(n, 1024 * 4096)]),
        NullAllocator);

    // Allocator list that creates one freelist for all objects
    alias A4 =
        Segregator!(
            64, AllocatorList!(
                (n) => ContiguousFreeList!(NullAllocator, 0, 64)(
                    GCAllocator.it.allocate(4096))),
            GCAllocator);

    A4 a;
    auto small = a.allocate(64);
    assert(small);
    a.deallocate(small);
    auto b1 = a.allocate(1024 * 8192);
    assert(b1 !is null); // still works due to overdimensioning
    b1 = a.allocate(1024 * 10);
    assert(b1.length == 1024 * 10);
}

unittest
{
    // Create an allocator based upon 4MB regions, fetched from the GC heap.
    import std.algorithm : max;
    import std.experimental.allocator.region : Region;
    AllocatorList!((n) => Region!GCAllocator(new void[max(n, 1024 * 4096)]),
        NullAllocator) a;
    const b1 = a.allocate(1024 * 8192);
    assert(b1 !is null); // still works due to overdimensioning
    const b2 = a.allocate(1024 * 10);
    assert(b2.length == 1024 * 10);
    a.deallocateAll();
}

unittest
{
    // Create an allocator based upon 4MB regions, fetched from the GC heap.
    import std.algorithm : max;
    import std.experimental.allocator.region : Region;
    AllocatorList!((n) => Region!()(new void[max(n, 1024 * 4096)])) a;
    auto b1 = a.allocate(1024 * 8192);
    assert(b1 !is null); // still works due to overdimensioning
    b1 = a.allocate(1024 * 10);
    assert(b1.length == 1024 * 10);
    a.deallocateAll();
}

unittest
{
    import std.algorithm : max;
    import std.experimental.allocator.region : Region;
    AllocatorList!((n) => Region!()(new void[max(n, 1024 * 4096)])) a;
    auto b1 = a.allocate(1024 * 8192);
    assert(b1 !is null);
    b1 = a.allocate(1024 * 10);
    assert(b1.length == 1024 * 10);
    a.allocate(1024 * 4095);
    a.deallocateAll();
    assert(a.empty == Ternary.yes);
}
