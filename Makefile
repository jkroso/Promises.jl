dependencies:
	mkdir $@ && ln -snf .. $@/Promises

test: dependencies
	@jest index.jl

.PHONY: test
