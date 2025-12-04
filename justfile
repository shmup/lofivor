# use bash
set shell := ["bash", "-c"]

default:
  @just build
  @just test

build:
    zig build

run: build
    zig build run

# build with release optimizations
release:
    zig build -Doptimize=ReleaseSafe

release-fast:
    zig build -Doptimize=ReleaseFast

release-small:
    zig build -Doptimize=ReleaseSmall

# windows cross-compile
windows:
    zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe

windows-fast:
    zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast

windows-small:
    zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall

# clean build artifacts
clean:
    rm -rf zig-out .zig-cache

# check for compile errors without building
check:
    zig build --summary all 2>&1 | head -50

test:
    zig build test
