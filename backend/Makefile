.PHONY: all run check test format format-check lint contract contract-test

DOMAIN_SOURCES := $(wildcard Workout/*.hs Workout/*/*.hs Import/*.hs Import/Fit/*.hs)
API_SOURCES := $(wildcard Api/*.hs Api/*/*.hs Api/*/*/*.hs)
STORAGE_SOURCES := $(wildcard Storage/*.hs Storage/*/*.hs)
CONTRACT_SOURCES := $(wildcard contract/*.hs)
TEST_SOURCES := $(wildcard test/*.hs)
FIT_CFLAGS = $(subst -I,-isystem ,$(shell pkg-config --cflags fitsdk))
FIT_LIBS = $(shell pkg-config --libs fitsdk)
NATIVE_FLAGS = -std=c++17 -Wall -Wextra -Werror -O2
HASKELL_SOURCES := Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) $(API_SOURCES) $(STORAGE_SOURCES) $(TEST_SOURCES) $(CONTRACT_SOURCES) test/fit/Main.hs test/storage/Main.hs

all: build/backend

build/backend: Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) build/native/fit_adapter.o Makefile
	mkdir -p build
	ghc --make -Wall -Werror -threaded -rtsopts -outputdir build Main.hs build/native/fit_adapter.o $(FIT_LIBS) -o $@

run: build/backend
	./build/backend

check:
	ghc -fno-code -Wall -Werror -i. $(DOMAIN_SOURCES) $(API_SOURCES) $(STORAGE_SOURCES)

build/domain-tests: $(DOMAIN_SOURCES) $(TEST_SOURCES) Makefile
	mkdir -p build/test
	ghc --make -Wall -Werror -i. -itest -outputdir build/test test/Main.hs -o $@

test: build/domain-tests
	./build/domain-tests

build/export-openapi: $(API_SOURCES) $(DOMAIN_SOURCES) contract/Main.hs Makefile
	mkdir -p build/contract
	ghc --make -Wall -Werror -i. -outputdir build/contract contract/Main.hs -o $@

build/openapi-3.0.json: build/export-openapi
	./build/export-openapi > $@

contract: build/openapi-3.0.json

build/contract-tests: $(API_SOURCES) $(DOMAIN_SOURCES) $(CONTRACT_SOURCES) test/Fixtures.hs Makefile
	mkdir -p build/contract-test
	ghc --make -Wall -Werror -i. -icontract -itest -outputdir build/contract-test contract/Check.hs -o $@

contract-test: build/contract-tests
	./build/contract-tests

.PHONY: migrate storage-test
migrate:
	IHP_MIGRATION_DIR=Application/Migration/ migrate

build/storage-tests: $(STORAGE_SOURCES) $(DOMAIN_SOURCES) $(API_SOURCES) test/storage/Main.hs test/Fixtures.hs Makefile
	mkdir -p build/storage-test
	ghc --make -Wall -Werror -threaded -i. -itest -outputdir build/storage-test test/storage/Main.hs -o $@

storage-test: build/storage-tests
	bash test/storage/run.sh

format:
	fourmolu --mode inplace $(HASKELL_SOURCES)

format-check:
	fourmolu --mode check $(HASKELL_SOURCES)

lint:
	hlint $(HASKELL_SOURCES)

# The SDK is a pinned Nix dependency; only our narrow adapter is built here.
build/native/fit_adapter.o: native/fit_adapter.cpp native/fit_adapter.h
	mkdir -p build/native
	$(CXX) $(NATIVE_FLAGS) $(FIT_CFLAGS) -Inative -c $< -o $@

build/fit-fixtures: test/fit/fixtures.cpp
	mkdir -p build
	$(CXX) $(NATIVE_FLAGS) $(FIT_CFLAGS) $< $(FIT_LIBS) -o $@

build/fit-tests: $(DOMAIN_SOURCES) test/fit/Main.hs build/native/fit_adapter.o
	mkdir -p build/fit-test
	ghc --make -Wall -Werror -threaded -i. -outputdir build/fit-test test/fit/Main.hs build/native/fit_adapter.o $(FIT_LIBS) -o $@

.PHONY: fit-test native-format native-format-check
fit-test: build/fit-fixtures build/fit-tests
	mkdir -p build/fit-fixtures-data
	./build/fit-fixtures build/fit-fixtures-data
	./build/fit-tests build/fit-fixtures-data

native-format:
	clang-format -i native/*.h native/*.cpp test/fit/*.cpp

native-format-check:
	clang-format --dry-run --Werror native/*.h native/*.cpp test/fit/*.cpp

# Instrument project-owned native code. The pinned SDK library is not instrumented.
.PHONY: native-sanitize
build/fit-native-sanitize: native/fit_adapter.cpp native/fit_adapter.h test/fit/native_tests.cpp
	mkdir -p build
	$(CXX) -std=c++17 -Wall -Wextra -Werror -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer $(FIT_CFLAGS) -Inative native/fit_adapter.cpp test/fit/native_tests.cpp $(FIT_LIBS) -o $@

native-sanitize: build/fit-native-sanitize build/fit-fixtures
	mkdir -p build/fit-fixtures-data
	./build/fit-fixtures build/fit-fixtures-data
	./build/fit-native-sanitize build/fit-fixtures-data/cycling.fit
