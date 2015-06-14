.PHONY: test graphs clean

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -cov -I../src/ -debug -wi

test:
	dmd $(FLAGS) $(SRC) -oftests
	./tests

looptest: loops.d
	dmd -O -inline -release -boundscheck=safeonly \
	looptest.d \
	../src/memory/allocators.d \
	../src/std/allocator.d \
	../src/containers/ttree.d \
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
