.PHONY: test graphs clean

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -cov -I../src/ -version=graphviz_debugging

test:
	dmd $(FLAGS) $(SRC) -oftests
	-./tests

clean:
	-rm tests
	-rm *.o
	-rm *.dot
	-rm *.png
	-rm *.lst

graphs: clean test
	parallel "dot -Tpng {} > {.}.png" ::: $(shell find . -name "graph*.dot")
