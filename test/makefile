.PHONY: test graphs clean

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -cov -I../src/

test:
	dmd $(FLAGS) $(SRC) -oftests
	./tests

clean:
	rm -f tests
	rm -f *.o
	rm -f *.dot
	rm -f *.png
	rm -f ..*.lst

graphs: clean
	dmd $(FLAGS) $(SRC) -oftests -version=graphviz_debugging
	-./tests
	parallel "dot -Tpng {} > {.}.png" ::: graph*.dot
