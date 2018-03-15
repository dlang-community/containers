/**
 * Templates for hashing types.
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module containers.internal.hash;

static if (hash_t.sizeof == 4)
{
	hash_t generateHash(T)(T value) nothrow @trusted
	{
		return typeid(T).getHash(&value);
	}
}
else
{
	hash_t generateHash(T)(T value) nothrow @trusted if (!is(T == string))
	{
		return typeid(T).getHash(&value);
	}

	hash_t generateHash(T)(T value) pure nothrow @nogc @trusted if (is(T == string))
	{
		immutable ulong fullIterCount = value.length >>> 3;
		immutable ulong remainderStart = fullIterCount << 3;
		ulong h;
		foreach (c; (cast(ulong*) value.ptr)[0 .. fullIterCount])
			h = (h ^ c) ^ (h >>> 4);
		foreach (c; value[remainderStart .. $])
			h += (h << 7) + c;
		return h;
	}
}
