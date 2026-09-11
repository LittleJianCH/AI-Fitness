.PHONY: all run check test format format-check lint

DOMAIN_SOURCES := $(wildcard Workout/*.hs Workout/*/*.hs Import/*.hs)
TEST_SOURCES := $(wildcard test/*.hs)
HASKELL_SOURCES := Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) $(TEST_SOURCES)

all: build/backend

build/backend: Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) Makefile
	mkdir -p build
	ghc --make -Wall -Werror -threaded -rtsopts -outputdir build Main.hs -o $@

run: build/backend
	./build/backend

check:
	ghc -fno-code -Wall -Werror -i. $(DOMAIN_SOURCES)

build/domain-tests: $(DOMAIN_SOURCES) $(TEST_SOURCES) Makefile
	mkdir -p build/test
	ghc --make -Wall -Werror -i. -itest -outputdir build/test test/Main.hs -o $@

test: build/domain-tests
	./build/domain-tests

format:
	fourmolu --mode inplace $(HASKELL_SOURCES)

format-check:
	fourmolu --mode check $(HASKELL_SOURCES)

lint:
	hlint $(HASKELL_SOURCES)
