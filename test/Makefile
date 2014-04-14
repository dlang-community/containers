.PHONY: test graphs clean

#GRAPHS=$(shell find ~/tmp/ -name "graph*.dot")
SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -g -I../src/

test:
	dmd $(FLAGS) $(SRC) -oftests
	-./tests

clean:
	-rm tests
	-rm *.o
	-rm ~/tmp/*.dot
	-rm ~/tmp/*.png

graphs: clean test
#	parallel "dot -Tpng {} > {.}.png" ::: $(GRAPHS)
