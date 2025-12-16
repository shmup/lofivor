# hysteresis in lofivor

## the problem without it

say your target is 8.33ms. your frame times naturally jitter: 8.2, 8.4, 8.3, 8.5, 8.2...

without hysteresis, every time it crosses 8.33ms you'd log "crossed threshold!" - potentially dozens of times per second. the log becomes useless noise.

## how the code works

from `sandbox_main.zig` lines 74-89:

```
was_above=false → need frame_ms > 10.33 (target + 2.0 margin) to flip to true
was_above=true  → need frame_ms < 8.33 (target) to flip back to false
```

this creates a "dead zone" between 8.33 and 10.33ms where no state change happens.

## the magnet analogy

the `was_above_target` boolean is like the magnet's current polarity. the frame time "pushing" past thresholds is like the magnetic field. the key insight: **the threshold you need to cross depends on which side you're currently on.**

if you're in "good" state, you need a significant spike (>10.33ms) before you flip to "bad". if you're in "bad" state, you only need to drop below 8.33ms to recover. this asymmetry is the hysteresis.

## real-world examples

- thermostat: heat on at 68°F, off at 72°F (prevents rapid on/off cycling)
- schmitt trigger in electronics: same concept, prevents noise from causing oscillation

the `THRESHOLD_MARGIN` of 2.0ms is the "width" of the hysteresis band - bigger = more stable but less responsive.
