/**
 * SIMD-accelerated Set
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */
module containers.simdset;

/**
 * Set implementation that is well suited for small sets and simple items.
 *
 * Uses SSE instructions to compare multiple elements simultaneously, but has
 * linear time complexity. Use this container when you need to
 *
 * Note: Only works on x86_64. Does NOT add GC ranges. Do not store pointers in
 * this container unless they are also stored somewhere else.
 */
version (D_InlineAsm_X86_64) struct SimdSet(T) if (T.sizeof == 1
	|| T.sizeof == 2 || T.sizeof == 4 || T.sizeof == 8)
{
	this(this) @disable;

	~this()
	{
		free(cast(void*) storage.ptr);
	}

	/**
	 * Params:
	 *     item = the item to check
	 * Returns:
	 *     true if the set contains the given item
	 */
	bool contains(T item) const pure nothrow @nogc
	{
		if (_length == 0)
			return false;
		bool retVal;
		immutable remainder = _length % (16 / T.sizeof);
		ushort mask = remainder == 0 ? 0xffff : (1 << (remainder * T.sizeof)) - 1;
		//ushort resultMask;
		ulong ptrStart = cast(ulong) storage.ptr;
		ulong ptrEnd = ptrStart + storage.length * T.sizeof;
		static if (T.sizeof == 1)
			ulong needle = (cast(ubyte) item) * 0x01010101_01010101;
		else static if (T.sizeof == 2)
			ulong needle = (cast(ushort) item) * 0x00010001_00010001;
		else static if (T.sizeof == 4)
			ulong needle = (cast(ulong) item) * 0x00000001_00000001;
		else static if (T.sizeof == 8)
			ulong needle = cast(ulong) item;
		else
			static assert(false);
		mixin(asmSearch());
	end:
		return retVal;
	}

	/**
	 * Inserts the given item into the set.
	 *
	 * Params:
	 *     item = the item to insert
	 * Returns:
	 *     true if the item was inserted or false if it was already present
	 */
	bool insert(T item)
	{
		if (contains(item))
			return false;
		if (storage.length > _length)
			storage[_length] = item;
		else
		{
			immutable size_t cl = (storage.length * T.sizeof);
			immutable size_t nl = cl + 16;
			storage = (cast(T*) realloc(storage.ptr, nl))[0 .. nl / T.sizeof];
			storage[_length] = item;
		}
		_length++;
		return true;
	}

	/**
	 * Removes the given item from the set.
	 *
	 * Params:
	 *     item = the time to remove
	 * Returns:
	 *     true if the item was removed, false if it was not present
	 */
	bool remove(T item)
	{
		import std.algorithm : countUntil;

		// TODO: Make this more efficient

		ptrdiff_t begin = countUntil(storage, item);
		if (begin == -1)
			return false;
		foreach (i; begin .. _length - 1)
			storage[i] = storage[i + 1];
		_length--;
		return true;
	}

	/**
	 * Returns:
	 *     the number of items in the set
	 */
	size_t length() const pure nothrow @nogc @property
	{
		return _length;
	}

	invariant
	{
		assert((storage.length * T.sizeof) % 16 == 0);
	}

private:

	static string asmSearch()
	{
		import std.string : format;

		static if (T.sizeof == 1)
			enum instruction = `pcmpeqb`;
		else static if (T.sizeof == 2)
			enum instruction = `pcmpeqw`;
		else static if (T.sizeof == 4)
			enum instruction = `pcmpeqd`;
		else static if (T.sizeof == 8)
			enum instruction = `pcmpeqq`;
		else
			static assert(false);

		static if (__VERSION__ >= 2067)
			string s = `asm pure nothrow @nogc`;
		else
			string s = `asm`;

		return s ~ `
		{
			mov R8, ptrStart;
			mov R9, ptrEnd;
			sub R8, 16;
			sub R9, 16;
			movq XMM0, needle;
			shufpd XMM0, XMM0, 0;
		loop:
			add R8, 16;
			movdqu XMM1, [R8];
			%s XMM1, XMM0;
			pmovmskb RAX, XMM1;
			//mov resultMask, AX;
			mov BX, AX;
			and BX, mask;
			cmp R8, R9;
			cmove AX, BX;
			popcnt AX, AX;
			test AX, AX;
			jnz found;
			cmp R8, R9;
			jl loop;
			mov retVal, 0;
			jmp end;
		found:
			mov retVal, 1;
			jmp end;
		}`.format(instruction);
	}

	T[] storage;
	size_t _length;
}

///
version (D_InlineAsm_X86_64) unittest
{
	import std.string : format;

	void testSimdSet(T)()
	{
		SimdSet!T set;
		assert(set.insert(1));
		assert(set.length == 1);
		assert(set.contains(1));
		assert(!set.insert(1));
		set.insert(0);
		set.insert(20);
		assert(set.contains(1));
		assert(set.contains(0));
		assert(!set.contains(10));
		assert(!set.contains(50));
		assert(set.contains(20));
		foreach (T i; 28 .. 127)
			set.insert(i);
		foreach (T i; 28 .. 127)
			assert(set.contains(i), "%d".format(i));
		foreach (T i; 28 .. 127)
			assert(set.remove(i));
		assert(set.length == 3, "%d".format(set.length));
		assert(set.contains(0));
		assert(set.contains(1));
		assert(set.contains(20));
		assert(!set.contains(28));
	}

	testSimdSet!ubyte();
	testSimdSet!ushort();
	testSimdSet!uint();
	testSimdSet!ulong();
	testSimdSet!byte();
	testSimdSet!short();
	testSimdSet!int();
	testSimdSet!long();
}

version (D_InlineAsm_X86_64) struct SimdSet(T) if (!(T.sizeof == 1
	|| T.sizeof == 2 || T.sizeof == 4 || T.sizeof == 8))
{
	import std.string : format;
	static assert (false, ("Cannot instantiate SimdSet of type %s because its size "
		~ "(%d) does not fit evenly into XMM registers.").format(T.stringof, T.sizeof));
}

private extern (C) void* realloc(void*, size_t);
private extern (C) void free(void*);
