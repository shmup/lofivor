set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
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

# run sandbox (GPU compute is default)
sandbox:
    zig build -Doptimize=ReleaseFast run

# auto-benchmark (ramps entities until performance degrades)
bench:
    zig build -Doptimize=ReleaseFast run -- --bench
    cat benchmark.log

# benchmark with CPU update path (for comparison)
bench-cpu:
    zig build -Doptimize=ReleaseFast run -- --bench --cpu
    cat benchmark.log

# software-rendered benchmark (for CI/headless servers)
[linux]
bench-sw:
    @zig build -Doptimize=ReleaseFast
    @xvfb-run -a ./zig-out/bin/sandbox --bench > /dev/null
    @cat benchmark.log

[windows]
bench-sw:
    @echo "bench-sw: windows doesn't have xvfb equivalent"
    @echo "use 'just bench' if you have a GPU, or run in WSL/linux CI"

[linux]
profile port="9876":
  # start Tracy: tracy-profiler -a 127.0.0.1 -p {{port}}
  zig build -Dtracy=true -Doptimize=ReleaseFast && TRACY_PORT={{port}} ./zig-out/bin/sandbox
