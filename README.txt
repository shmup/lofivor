lofivor
=======

sandbox stress test for measuring entity rendering performance on weak hardware.
written in zig with raylib.

build & run
-----------

    zig build run

controls
--------

    +/-      add/remove 1000 entities
    shift    hold for 10x (10000 entities)
    space    pause/resume
    r        reset

output
------

benchmark.log is written to project root with frame timing data.
