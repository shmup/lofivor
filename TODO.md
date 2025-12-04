# lockstep artillery - build roadmap

## phase 1: foundation

- [ ] set up build.zig with raylib-zig dependency
- [ ] create fixed-point math module (Fixed struct, add/sub/mul/div)
- [ ] create trig lookup tables (sin/cos at comptime)
- [ ] basic window opens with raylib

## phase 2: single-player simulation

- [ ] define GameState, Player, Projectile structs
- [ ] terrain generation (random jagged line)
- [ ] cannon aiming (angle adjustment with keys)
- [ ] power adjustment
- [ ] fire projectile
- [ ] projectile physics (gravity, movement)
- [ ] terrain collision detection
- [ ] player hit detection
- [ ] turn switching after shot resolves

## phase 3: rendering

- [ ] draw terrain as connected line segments
- [ ] draw players as geometric shapes
- [ ] draw cannon angle indicator
- [ ] draw power meter
- [ ] draw projectile with trail (last N positions)
- [ ] implement bloom shader (blur.fs)
- [ ] render-to-texture pipeline for glow effect
- [ ] explosion effect (expanding circle)

## phase 4: local two-player

- [ ] split keyboard input (player 1: wasd+space, player 2: arrows+enter)
- [ ] verify determinism by running two simulations side-by-side
- [ ] add checksum verification

## phase 5: networking

- [ ] UDP socket wrapper (bind, send, receive)
- [ ] define packet format (INPUT, SYNC, PING, PONG)
- [ ] host mode: listen for connection, send initial SYNC
- [ ] guest mode: connect, receive SYNC, start simulation
- [ ] input exchange each frame
- [ ] handle packet loss (resend on timeout)
- [ ] checksum exchange and desync detection
- [ ] latency display

## phase 6: polish

- [ ] wind indicator
- [ ] health bars
- [ ] win/lose screen
- [ ] rematch option
- [ ] sound effects (optional, breaks no-dependency purity)

## known pitfalls to watch

- [ ] don't use floats in simulation
- [ ] don't iterate hashmaps
- [ ] don't use @sin/@cos - use lookup tables
- [ ] always process inputs in same order (player 0 then player 1)
- [ ] serialize terrain heights as fixed-point, not float

## stretch goals

- [ ] destructible terrain (explosion removes pixels)
- [ ] multiple weapon types
- [ ] rollback netcode (predict, rewind, replay on correction)
- [ ] replay file save/load
- [ ] web build via emscripten
