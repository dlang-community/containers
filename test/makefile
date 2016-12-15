.PHONY: test graphs clean

DC?=dmd
SRC:=$(shell find ../src/ -name "*.d") $(shell find ../experimental_allocator -name "*.d")
FLAGS:=-unittest -main -g -cov -I../src/ -debug -wi
FLAGS32:=$(FLAGS) -m32

all: test test_32 compile_test compile_test_32 external_allocator_test external_allocator_test_32
	./tests
	./tests_32
	./compile_test
	./compile_test_32
	./external_allocator_test
	./external_allocator_test_32

test: $(SRC)
	$(DC) $(FLAGS) $(SRC) -oftests
test_32: $(SRC)
	$(DC) $(FLAGS32) $(SRC) -oftests_32

compile_test: compile_test.d $(SRC)
	$(DC) $(FLAGS) compile_test.d $(SRC) -ofcompile_test
compile_test_32: compile_test.d $(SRC)
	$(DC) $(FLAGS32) compile_test.d $(SRC) -ofcompile_test_32

external_allocator_test: external_allocator_test.d $(SRC)
	$(DC) $(FLAGS) external_allocator_test.d $(SRC) -ofexternal_allocator_test
external_allocator_test_32: external_allocator_test.d $(SRC)
	$(DC) $(FLAGS32) external_allocator_test.d $(SRC) -ofexternal_allocator_test_32

looptest: looptest.d
	$(DC) looptest.d -inline -O -release \
		../src/memory/allocators.d \
		../src/containers/ttree.d \
		../src/containers/internal/node.d \
		-I../src/ \

clean:
	rm -f tests
	rm -f *.o
	rm -f *.dot
	rm -f *.png
	rm -f ..*.lst
	rm -f looptest

graphs: clean
	$(DC) $(FLAGS) $(SRC) -oftests -version=graphviz_debugging
	-./tests
	parallel "dot -Tpng {} > {.}.png" ::: graph*.dot
