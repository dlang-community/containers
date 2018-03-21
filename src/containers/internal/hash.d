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

	/**
	 * A variant of the FNV-1a (64) hashing algorithm.
	 */
	hash_t generateHash(T)(T value) pure nothrow @nogc @trusted if (is(T == string))
	{
		hash_t h = 0xcbf29ce484222325;
		foreach (const ubyte c; cast(ubyte[]) value)
		{
			h ^= ((c - ' ') * 13);
			h *= 0x100000001b3;
		}
		return h;
	}
}
