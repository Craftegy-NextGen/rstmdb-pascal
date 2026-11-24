FPC       ?= fpc
FPCFLAGS  ?= -Mdelphi -Sh -O2 -vewn -Fi./src -Fu./src -Fu./tests -FUlib -FEbin
FPC_TEST_FLAGS := $(FPCFLAGS) -gh -gl

.PHONY: all build test examples live-test clean

all: build

build:
	@mkdir -p lib bin
	$(FPC) $(FPCFLAGS) tests/RunTests.dpr

test:
	@mkdir -p lib bin
	$(FPC) $(FPC_TEST_FLAGS) tests/RunTests.dpr
	./bin/RunTests

examples:
	@mkdir -p lib bin
	$(FPC) $(FPCFLAGS) examples/BasicUsage.dpr
	$(FPC) $(FPCFLAGS) examples/WatchEvents.dpr

live-test:
	@mkdir -p lib bin
	$(FPC) $(FPC_TEST_FLAGS) tests/RunLiveIntegration.dpr
	./bin/RunLiveIntegration

clean:
	@mkdir -p lib bin
	find lib bin -mindepth 1 -delete
	find . -type f \( -name '*.ppu' -o -name '*.o' -o -name '*.dcu' \) -delete
