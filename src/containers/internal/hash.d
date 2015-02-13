module containers.internal.hash;

hash_t generateHash(T)(T value) nothrow @trusted
{
	import std.functional : unaryFun;
	hash_t h = typeid(T).getHash(&value);
	h ^= (h >>> 20) ^ (h >>> 12);
	return h ^ (h >>> 7) ^ (h >>> 4);
}
