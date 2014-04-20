.PHONY: test graphs clean

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -cov -I../src/

test:
	dmd $(FLAGS) $(SRC) -oftests
	./tests

clean:
	-rm tests
	-rm *.o
	-rm *.dot
	-rm *.png
	-rm ..*.lst

graphs: clean
	dmd $(FLAGS) $(SRC) -oftests -version=graphviz_debugging
	parallel "dot -Tpng {} > {.}.png" ::: $(shell find . -name "graph*.dot")
