FPC       ?= fpc
FPCFLAGS  ?= -Mdelphi -Sh -O2 -vewn -Fi./src -Fu./src -FUlib -FEbin
FPC_TEST_FLAGS := $(FPCFLAGS) -gh -gl

.PHONY: all build test clean

all: build

build:
	@mkdir -p lib bin
	@echo "Add unit build targets once SDK units are implemented under src/."

test:
	@mkdir -p lib bin
	@echo "Add test runner execution ($(FPC) $(FPC_TEST_FLAGS)) once tests/ runner exists."

clean:
	rm -rf lib/* bin/*
	find . -type f \( -name '*.ppu' -o -name '*.o' -o -name '*.dcu' \) -delete
