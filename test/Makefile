.PHONY: test

SRC=$(shell find ../src/ -name "*.d")
FLAGS=-unittest -main -cov=72 -g -I../src/

test:
	dmd $(FLAGS) $(SRC) -oftests
	./tests
	echo "Tests passed"

clean:
	@rm tests
	@rm $(shell . find -name "*.o")
