.PHONY: all run

all: build/backend

build/backend: Main.hs Api.hs Config.hs Makefile
	mkdir -p build
	ghc --make -Wall -Werror -threaded -rtsopts -outputdir build Main.hs -o $@

run: build/backend
	./build/backend
