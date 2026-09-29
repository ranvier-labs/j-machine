# Lookbook: a produced motion piece about the J-Machine

A short film in the style of a fashion lookbook: a title, eight numbered
"looks", an end card. Every look is one subject drawn from real machine data,
with a monospace HUD layer (tracking brackets, labels, a split-flap board, a
stats ticker, timecode, a waveform of the soundtrack), lyric-style captions
that appear word by word, and bold display type. Film grain, a vignette and a
one-pixel chroma shift are added when the frames are encoded.

## Pipeline

    node tools/motion/capture.mjs            # runs the example programs headlessly → out/motion/data/*.json
    python3 tools/motion/music.py 45 128     # 45-bar sectioned 128 BPM track → out/motion/music.wav + music.json
    python3 tools/motion/music_calm.py --pulse   # calmer variant: piano, strings, soft kick and brushes → out/motion/music-calmer.wav
    python3 tools/motion/music_calm.py           # calm variant without drums → out/motion/music-calm.wav
    node tools/motion/ide_stills.mjs         # drives the tour in Chrome, screenshots each tool in use → out/motion/ide/
    node tools/motion/render.mjs --stills 3,22,45   # PNG frames at those seconds, for review
    node tools/motion/render.mjs --label v4  # every frame at 30 fps → out/lookbook-v4.mp4 and a 720p copy

Pick a soundtrack with `--music out/motion/music-calmer`; the default is
`out/motion/music`. Renders never overwrite: without `--label` the file is named after the short
commit id, and a taken name gets a counter. Keep every cut.

`capture.mjs` records, per program, retired instructions and message
traffic per node every few thousand cycles, and every change of a node's
framebuffer. `piece.js` turns that into the looks; `scene.html` is the stage
and the HUD styles; `render.mjs` screenshots each instant with Playwright
(Chrome, 1920×1080) and hands the frames to ffmpeg with the music.

Node 20 or newer from `/opt/homebrew/bin` (Playwright and the simulator need
it), Chrome, ffmpeg and numpy. Rendering the 104-second piece takes about
seven minutes; capturing the 512-node programs takes longer than the rest
combined and is bounded by the `budget` seconds in `capture.mjs`.

## Changing the piece

- Cuts sit on bars of the 128 BPM grid (`BAR` in `piece.js`); every look has
  `bars`, an `art(u, dur)` drawing the imagery on the canvas and a
  `hud(u, t, dur)` returning the overlay for local time `u`.
- Act III draws the workbench stills from `out/motion/ide/` with `artStill`,
  pushing toward one window; `winBracket` places the HUD brackets from the
  window boxes recorded in `stills.json`. Photographs or generated stills
  can be added the same way.
- The soundtrack is generated and sectioned but still a stand-in for a
  produced track. The lyric sheet below is the brief: generate a track from it (any music model), save it as
  `out/motion/music.wav`, write an RMS envelope to `music.json` at 30 Hz (the
  end of `music.py` shows the format), and re-render.

## Structure

Three acts on a 45-bar, 128 BPM grid (84 s): an intro, a build into a drop
at bar 9 for Act II, a break for the two programs at bar 25, a second drop
for Act III at bar 31, and an outro from bar 41.

| Bars | Act | Look | Claim and its source |
|---|---|---|---|
| 0–3 | | Title | built at MIT, 1988–1993, for many small communicating threads; spec card from Noakes, Wallach & Dally, ISCA 1993 |
| 3–9 | I · The cost | Cost | one-way message overhead in cycles: nCUBE/2 3,200, Intel Delta 2,880, CM-5 2,838 (vendor libraries), 460 and 109 with Active Messages, J-Machine 11 (ISCA 1993, Table 1) |
| 9–25 | II · How it works | Mesh, Arrival, Tags, Future | measured on the RTL: 21 hops in 28 cycles; handler dispatched 18 cycles after the first word arrives and before the last word (mesh_rainbow.c, packet 4); seven real tagged words from remote_call.c's image (INT, BOOL, ADDR, IP, MSG, INST, FUT); the future resolved to INT 142 at cycle 5,222 |
| 25–31 | II | Life, Heat | 14 live cells after 16 generations and a last-sweep change of 196, both matching host models |
| 31–41 | III · Run it | Workbench, The call | the RTL compiled by Verilator runs in the tab; one slide names the tools; Message-Driven C and its Lean 4 compiler in WebAssembly |
| 41–45 | | End | j-machine.pages.dev, the repository, and the sources of the numbers |

Every number on screen is either quoted from the 1993 paper, with the
paper named on screen, or measured on the simulator, with the program
named on screen. The constants sit at the top of `piece.js`.

## Script

    The J-Machine was built at MIT between 1988 and 1993. It was designed for programs made of many small threads that message each other constantly.
    Act I. The cost.
    In 1993, sending one message cost thousands of processor cycles with the vendors' libraries. Tuned software brought it to a few hundred. The J-Machine cut it to 11 by doing in hardware what the others did in software.
    Act II. How it works.
    Node 0 calls the four far corners of an 8×8×8 cube. Each message goes along x, then y, then z, one cycle per hop.
    The first word crosses 21 hops in 28 cycles. The hardware queues it and starts the handler 18 cycles later, while the rest is still arriving. Nobody polls.
    A number, a flag, an address, a code pointer, a message header, machine code. And a future: a result that has not been computed yet.
    remote_add(20, 22)@1 returns at once with a word tagged FUT. Reading it before the reply faults and suspends the thread. The reply writes INT 142 and wakes it.
    Each node owns a 4×4 tile. Node 15 collects the edges and sends every tile its border. After 16 generations 14 cells are alive, the same as a simulation on the host.
    Two spots held hot, two corners held cold. Each sweep sets every cell to the mean of its neighbours. The last sweep changes the plate by 196 in total, the same as a model on the host.
    Act III. Run it.
    The MDP and its router, compiled from the RTL by Verilator, run cycle for cycle in a browser tab. Around them, the tools to see what every node and every message is doing. Nothing to install.
    Message-Driven C is C plus one operator: a call suffixed with @node runs on that node. The compiler is written in Lean 4 and runs in the tab as WebAssembly. No toolchain to install.
    Start at j-machine.pages.dev. 1993 figures: Noakes, Wallach and Dally, ISCA 1993. All other numbers were measured on the simulator.
