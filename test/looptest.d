module looptest;

import std.stdio : writeln;
import containers.unrolledlist : UnrolledList;
import containers.ttree : TTree;

private enum MAGIC_LOOP_CONSTANT = 100_000_000;

/// T-Tree insert & destructor test
private void a()
{
	ulong counter = 0;
	while (true)
	{
		TTree!int ints;
		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.insert(i);
		++counter;
		writeln(__FUNCTION__, ": ", counter);
	}
}

/// T-Tree insert & remove test
private void b()
{
	ulong counter = 0;
	TTree!int ints;
	while (true)
	{
		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.insert(i);

		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.remove(i);
		++counter;
		writeln(__FUNCTION__, ": ", counter);
	}
}

// Unrolled list insert & destructor test
private void c()
{
	ulong counter = 0;
	while (true)
	{
		UnrolledList!int ints;
		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.insert(i);
		++counter;
		writeln(__FUNCTION__, ": ", counter);
	}
}

// Unrolled list insert & remove test
private void d()
{
	UnrolledList!int ints;
	ulong counter = 0;
	while (true)
	{
		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.insert(i);

		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.popBack();
		++counter;
		writeln(__FUNCTION__, ": ", counter);
	}
}

// Phobos Red-Black tree
private void e()
{
	import std.container.rbtree : RedBlackTree;

	ulong counter = 0;
	while (true)
	{
		auto ints = new RedBlackTree!int;
		foreach (i; 0 .. MAGIC_LOOP_CONSTANT)
			ints.insert(i);
		++counter;
		writeln(__FUNCTION__, ": ", counter);
	}
}

void main()
{
	//	a();
	//	b();
	//	c();
	//	d();
	e();
}
