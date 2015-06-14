.PHONY: test graphs clean

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -cov -I../src/ -debug -wi

test:
	dmd $(FLAGS) $(SRC) -oftests
	./tests

looptest: looptest.d
	dmd looptest.d -inline -O -release \
		../src/memory/allocators.d \
		../src/containers/ttree.d \
		../src/containers/internal/node.d \
		../src/std/experimental/allocator/package.d \
		../src/std/experimental/allocator/common.d \
		../src/std/experimental/allocator/gc_allocator.d \
		../src/std/experimental/allocator/mallocator.d \
		../src/std/experimental/allocator/typed.d \
		-I../src/

clean:
	rm -f tests
	rm -f *.o
	rm -f *.dot
	rm -f *.png
	rm -f ..*.lst
	rm -f looptest

graphs: clean
	dmd $(FLAGS) $(SRC) -oftests -version=graphviz_debugging
	-./tests
	parallel "dot -Tpng {} > {.}.png" ::: graph*.dot
