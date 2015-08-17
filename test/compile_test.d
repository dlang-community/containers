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
	testContainerSingleVal!(Container)();
	testContainerSingleRef!(Container)();
}

private void testContainerSingleVal(alias Container)()
{
	Container!(int) mm;
	Container!(const int) mc;
	Container!(immutable int) mi;

	const Container!(int) cm;
	const Container!(const int) cc;
	const Container!(immutable int) ci;

	immutable Container!(int) im;
	immutable Container!(const int) ic;
	immutable Container!(immutable int) ii;

	checkFunctionality!(int)(mm);
	checkFunctionality!(const int)(mc);
	checkFunctionality!(immutable int)(mi);

	checkFunctionality!(int)(cm);
	checkFunctionality!(const int)(cc);
	checkFunctionality!(immutable int)(ci);

	checkFunctionality!(int)(im);
	checkFunctionality!(const int)(ic);
	checkFunctionality!(immutable int)(ii);
}

private void testContainerSingleRef(alias Container)()
{
	Container!(int*) mm;
	Container!(const int*) mc;
	Container!(immutable int*) mi;

	const Container!(int*) cm;
	const Container!(const int*) cc;
	const Container!(immutable int*) ci;

	immutable Container!(immutable int*) ii;

	checkFunctionality!(int*)(mm);
	checkFunctionality!(const int*)(mc);
	checkFunctionality!(immutable int*)(mi);

	checkFunctionality!(const(int)*)(cm);
	checkFunctionality!(const int*)(cc);
	checkFunctionality!(immutable int*)(ci);

	checkFunctionality!(immutable int*)(ii);
}

private void testContainerDouble(alias Container)()
{
	testContainerDoubleVal!(Container)();
	testContainerDoubleRef!(Container)();
}

private void testContainerDoubleVal(alias Container)()
{
	{
		Container!(int, int) mmm;
		Container!(int, const int) mmc;
		Container!(int, immutable int) mmi;

		Container!(const int, int) mcm;
		Container!(const int, const int) mcc;
		Container!(const int, immutable int) mci;

		Container!(immutable int, int) mim;
		Container!(immutable int, const int) mic;
		Container!(immutable int, immutable int) mii;

		checkFunctionality!(int)(mmm);
		checkFunctionality!(const int)(mmc);
		checkFunctionality!(immutable int)(mmi);

		checkFunctionality!(int)(mcm);
		checkFunctionality!(const int)(mcc);
		checkFunctionality!(immutable int)(mci);

		checkFunctionality!(int)(mim);
		checkFunctionality!(const int)(mic);
		checkFunctionality!(immutable int)(mii);
	}

	{
		const Container!(int, int) cmm;
		const Container!(int, const int) cmc;
		const Container!(int, immutable int) cmi;

		const Container!(const int, int) ccm;
		const Container!(const int, const int) ccc;
		const Container!(const int, immutable int) cci;

		const Container!(immutable int, int) cim;
		const Container!(immutable int, const int) cic;
		const Container!(immutable int, immutable int) cii;

		checkFunctionality!(int)(cmm);
		checkFunctionality!(const int)(cmc);
		checkFunctionality!(immutable int)(cmi);

		checkFunctionality!(int)(ccm);
		checkFunctionality!(const int)(ccc);
		checkFunctionality!(immutable int)(cci);

		checkFunctionality!(int)(cim);
		checkFunctionality!(const int)(cic);
		checkFunctionality!(immutable int)(cii);
	}

	{
		immutable Container!(int, int) imm;
		immutable Container!(int, const int) imc;
		immutable Container!(int, immutable int) imi;

		immutable Container!(const int, int) icm;
		immutable Container!(const int, const int) icc;
		immutable Container!(const int, immutable int) ici;

		immutable Container!(immutable int, int) iim;
		immutable Container!(immutable int, const int) iic;
		immutable Container!(immutable int, immutable int) iii;

		checkFunctionality!(int)(imm);
		checkFunctionality!(const int)(imc);
		checkFunctionality!(immutable int)(imi);

		checkFunctionality!(int)(icm);
		checkFunctionality!(const int)(icc);
		checkFunctionality!(immutable int)(ici);

		checkFunctionality!(int)(iim);
		checkFunctionality!(const int)(iic);
		checkFunctionality!(immutable int)(iii);
	}
}

private void testContainerDoubleRef(alias Container)()
{
	{
		Container!(int, int*) mmm;
		Container!(int, const int*) mmc;
		Container!(int, immutable int*) mmi;

		Container!(const int, int*) mcm;
		Container!(const int, const int*) mcc;
		Container!(const int, immutable int*) mci;

		Container!(immutable int, int*) mim;
		Container!(immutable int, const int*) mic;
		Container!(immutable int, immutable int*) mii;

		checkFunctionality!(int*)(mmm);
		checkFunctionality!(const int*)(mmc);
		checkFunctionality!(immutable int*)(mmi);

		checkFunctionality!(int*)(mcm);
		checkFunctionality!(const int*)(mcc);
		checkFunctionality!(immutable int*)(mci);

		checkFunctionality!(int*)(mim);
		checkFunctionality!(const int*)(mic);
		checkFunctionality!(immutable int*)(mii);
	}

	{
		const Container!(int, int*) cmm;
		const Container!(int, const int*) cmc;
		const Container!(int, immutable int*) cmi;

		const Container!(const int, int*) ccm;
		const Container!(const int, const int*) ccc;
		const Container!(const int, immutable int*) cci;

		const Container!(immutable int, int*) cim;
		const Container!(immutable int, const int*) cic;
		const Container!(immutable int, immutable int*) cii;

		checkFunctionality!(const int*)(cmm);
		checkFunctionality!(const int*)(cmc);
		checkFunctionality!(immutable int*)(cmi);

		checkFunctionality!(const int*)(ccm);
		checkFunctionality!(const int*)(ccc);
		checkFunctionality!(immutable int*)(cci);

		checkFunctionality!(const int*)(cim);
		checkFunctionality!(const int*)(cic);
		checkFunctionality!(immutable int*)(cii);
	}

	{
		immutable Container!(int, int*) imm;
		immutable Container!(int, const int*) imc;
		immutable Container!(int, immutable int*) imi;

		immutable Container!(const int, int*) icm;
		immutable Container!(const int, const int*) icc;
		immutable Container!(const int, immutable int*) ici;

		immutable Container!(immutable int, int*) iim;
		immutable Container!(immutable int, const int*) iic;
		immutable Container!(immutable int, immutable int*) iii;

		checkFunctionality!(immutable int*)(imm);
		checkFunctionality!(immutable int*)(imc);
		checkFunctionality!(immutable int*)(imi);

		checkFunctionality!(immutable int*)(icm);
		checkFunctionality!(immutable int*)(icc);
		checkFunctionality!(immutable int*)(ici);

		checkFunctionality!(immutable int*)(iim);
		checkFunctionality!(immutable int*)(iic);
		checkFunctionality!(immutable int*)(iii);
	}
}

private void checkFunctionality(Type, Container)(ref Container container)
{
	auto r = container[];
	pragma(msg, "type of " ~ Container.stringof ~ ".front is " ~ typeof(r.front).stringof);
	static assert(is(typeof(r.front()) == Type));
	static assert(is(typeof(container.length) == size_t));
	assert(container.length == 0);
}

unittest
{
	//	testContainerDouble!(HashMap)();
	//	testContainerDouble!(TreeMap)();
	testContainerSingle!(HashSet)();
//	testContainerSingle!(UnrolledList)();
//	testContainerSingle!(OpenHashSet)();
	//	testContainerSingle!(SimdSet)();
//	testContainerSingle!(SList)();
//	testContainerSingle!(TTree)();
}
