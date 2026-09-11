.PHONY: all run check test format format-check lint

DOMAIN_SOURCES := $(wildcard Workout/*.hs Workout/*/*.hs Import/*.hs Import/Fit/*.hs)
TEST_SOURCES := $(wildcard test/*.hs)
FIT_CFLAGS = $(subst -I,-isystem ,$(shell pkg-config --cflags fitsdk))
FIT_LIBS = $(shell pkg-config --libs fitsdk)
NATIVE_FLAGS = -std=c++17 -Wall -Wextra -Werror -O2
HASKELL_SOURCES := Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) $(TEST_SOURCES) test/fit/Main.hs

all: build/backend

build/backend: Main.hs Api.hs Config.hs $(DOMAIN_SOURCES) build/native/fit_adapter.o Makefile
	mkdir -p build
	ghc --make -Wall -Werror -threaded -rtsopts -outputdir build Main.hs build/native/fit_adapter.o $(FIT_LIBS) -o $@

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
