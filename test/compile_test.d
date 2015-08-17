import containers.hashmap;
import containers.hashset;
import containers.unrolledlist;
import containers.openhashset;
import containers.simdset;
import containers.slist;
import containers.treemap;
import containers.ttree;

private void testContainerSingle(alias Container)()
{
	testContainerSingle2!(Container)();
	testContainerSingle2!(const(Container))();
	testContainerSingle2!(immutable(Container))();
}

private  void testContainerDouble(alias Container)()
{
	testContainerDouble2!(Container)();
	testContainerDouble2!(const(Container))();
	testContainerDouble2!(immutable(Container))();
}

private void testContainerSingle2(alias Container)()
{
	Container!(int) m;
	Container!(const int) c;
	Container!(immutable int) i;

	checkFunctionality!(int)(m);
	checkFunctionality!(const int)(c);
	checkFunctionality!(immutable int)(i);
}

private void testContainerDouble2(alias Container)()
{
	Container!(int, int) mm;
	Container!(int, const int) mc;
	Container!(int, immutable int) mi;
	Container!(const int, int) cm;
	Container!(const int, const int) cc;
	Container!(const int, immutable int) ci;
	Container!(immutable int, int) im;
	Container!(immutable int, const int) ic;
	Container!(immutable int, immutable int) ii;

	checkFunctionality!(int)(mm);
	checkFunctionality!(constint)(mc);
	checkFunctionality!(immutable int)(mi);
	checkFunctionality!(int)(cm);
	checkFunctionality!(constint)(cc);
	checkFunctionality!(immutable int)(ci);
	checkFunctionality!(int)(im);
	checkFunctionality!(constint)(ic);
	checkFunctionality!(immutable int)(ii);
}

private void checkFunctionality(Type, Container)(ref Container container)
{
	auto r = container[];
	static assert(is(typeof(r.front()) == Type));
	static assert(is(typeof(container.length) == size_t));
	assert (container.length == 0);
}

unittest
{
//	testContainerDouble!(HashMap)();
//	testContainerDouble!(TreeMap)();
	testContainerSingle!(HashSet)();
	testContainerSingle!(UnrolledList)();
	testContainerSingle!(OpenHashSet)();
//	testContainerSingle!(SimdSet)();
	testContainerSingle!(SList)();
	testContainerSingle!(TTree)();
}
