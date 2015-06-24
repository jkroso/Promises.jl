
dependencies: dependencies.json
	@packin install --folder $@ --meta $<
	@ln -snf .. $@/Promises

test: dependencies
	@$</jest/bin/jest $@

.PHONY: test
