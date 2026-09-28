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
    node tools/motion/ide_stills.mjs         # drives the tour in Chrome, screenshots each tool in use → out/motion/ide/
    node tools/motion/render.mjs --stills 3,22,45   # PNG frames at those seconds, for review
    node tools/motion/render.mjs --label v4  # every frame at 30 fps → out/lookbook-v4.mp4 and a 720p copy

Renders never overwrite: without `--label` the file is named after the short
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

Three acts on a 45-bar, 128 BPM grid (84 s). The soundtrack's sections
follow them: a quiet intro with clock ticks under Act I, a build and a drop
into Act II at bar 9, a break for the Life and heat looks at bar 23, a second
drop with a lead line for Act III at bar 29, and an outro from bar 41.

| Bars | Act | Look | Point |
|---|---|---|---|
| 0–3 | | Title | one idea: a message should cost almost nothing |
| 3–9 | I · The cost | 01 Waiting | in 1988 one send cost hundreds of instructions; the processor waited |
| 9–23 | II · The machine | 02 Word, 03 Mesh, 04 Dispatch, 05 Hotspot | tagged words, 512 nodes in dimension-order routing, handler runs 5 cycles after the last word (measured), contention shown |
| 23–29 | II | 06 Life, 07 Heat | real programs on the real cycles |
| 29–41 | III · Yours | 08 The workbench, 09 The call, 10 Free | one slide names the tools (workbench, integrated debugger, packet inspector, network monitor, graphical display) while the imagery cuts to each; Message-Driven C and its Lean 4 compiler in the tab; Apache 2.0 |
| 41–45 | | End | start at j-machine.pages.dev |

## Lyric sheet

    A machine from 1991, built on one idea. A message should cost almost nothing.
    Act one. The cost.
    Look 01. On the machines of its day, sending one message cost hundreds of instructions. The processor waited.
    Act two. The machine.
    Look 02. Thirty-six bits to a word. Four of them say what it is. The hardware knows a message when it sees one.
    Look 03. Five hundred twelve nodes in a cube. Eight by eight by eight. Routed in dimension order: x, then y, then z.
    Look 04. The handler runs five cycles after the last word leaves the sender. Twenty-one hops away. Nobody polled. Nobody copied.
    Look 05. Four senders, thirty-two messages, one address. Contention is visible, not hidden.
    Look 06. Sixteen tiles trade their edges. Sixteen generations of life. Fourteen survive.
    Look 07. Heat leaves the hot corner, one sweep at a time. Real programs. Real cycles.
    Act three. Yours.
    Look 08. The whole machine, gate for gate, in a browser tab. And the tools around it: workbench, integrated debugger, packet inspector, network monitor, graphical display. No hardware. No install. Nothing hidden.
    Look 09. C plus one operator: call a function at a node. The compiler is written in Lean 4 and runs in the tab as WebAssembly. No toolchain to install.
    Look 10. Open source. Apache 2.0. Free. The RTL, the compiler, the workbench.
    Start at j-machine.pages.dev. Every cycle count in this film was measured on the simulator.
