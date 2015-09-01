/**
 * Templates for hashing types.
 * Copyright: © 2015 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module containers.internal.hash;

hash_t generateHash(T)(T value) nothrow @trusted
{
	import std.functional : unaryFun;
	hash_t h = typeid(T).getHash(&value);
	h ^= (h >>> 20) ^ (h >>> 12);
	return h ^ (h >>> 7) ^ (h >>> 4);
}
