module loops;

import containers.ttree;

void main() @nogc
{
	TTree!int ints;

	while (true)
	{
		foreach (i; 0 .. 100_000_000)
			ints.insert(i);

		foreach (i; 0 .. 100_000_000)
			ints.remove(i);
	}
}
