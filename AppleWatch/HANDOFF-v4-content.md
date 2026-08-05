# Handoff — D-Tector watch port, v4-style content

Open a new chat in `/Users/boz/D-Tector-v2-master 2/AppleWatch` and paste
the **Prompt** section. The project memory file loads automatically in
that directory and already holds the build commands, the QA launch
arguments and a long list of hard-won gotchas — the prompt only needs to
cover what is left to do.

---

## Prompt

I'm porting the Unity game in the parent directory (a fan-made D-Tector
/ Digimon Frontier v-pet) to Apple Watch. Read `MEMORY.md` and
`dtector-watch-port.md` in your memory directory first — they hold the
build and QA commands plus several non-obvious traps that cost a lot of
time to find. The monochrome port is working and verified.

### What was just finished

The **Susanoomon evolution cutscene** is done — a step-for-step
transcription of `Animations.SusanoomonEvolution` (20.0s: shared charge,
KaiserGreymon's five spirits, MagnaGarurumon's five, the kid sweeping up,
ten spirit pairs converging, then the curtain reveal). It triggers when
the player's digimon becomes `susanoomon`, and can be inspected with
`--qa-cutscene susanoomon [--qa-cutscene-offset S] [--qa-freeze]`.
Verified in the simulator. The build is green.

### What I want next, in this order

**1. Pipe Monsters mini-game.** This is Version 4's exclusive game
(whack-a-mole style). There is **no reference implementation** — the
original Unity project only reserved `App.EnergyWars` / `App.DigiCatch`
enum slots and never wrote any game. So this is original work, like the
Energy Wars and Digi-Catch games already in `UnityDTMiniGames.swift` —
follow those for structure (`startMiniGame`, `updateMiniGame`,
`miniGameA/Left/Right`, a view in `UnityDTRootView`, a QA screen entry).
Build it out of sprites the game already has.

**2. Worlds from Adventure / 02 / Tamers.** I want a crossover: extra
worlds beyond the nine Frontier ones. What exists and what does not:

- `worlds.json` holds 9 worlds / 52 areas. Shape of a world:
  `{number, worldSprite, areas[{number, map, distance, coords{x,y}}],
  bosses, multiMap, semibossMode, semibosses, shuffle, removePlayer}`.
- Map art lives in `Assets/Resources/Sprites/Maps/` — **16 PNGs, all
  `frontier_*`, 32x32 1-bit**. There is no art for other seasons, so new
  worlds need new map sprites drawn (they are simple 32x32 one-bit
  images; a multi-map world uses four of them).
- The roster is large enough to stock them. Bosses I confirmed present:
  Adventure — devimon, etemon, apocalymon, metalseadramon; 02 —
  okuwamon, malomyotismon, blackwargreymon; Tamers — beelzemon,
  megidramon, sakuyamon, justimon, zhuqiaomon, vikaralamon.

Do the data first and let the new worlds reuse existing map art so it is
playable, then replace the art. Show me a world before building all of
them.

### Ground rules that have served us well

- The Unity C# in the parent directory is the source of truth. When you
  are unsure what the original does, read it — don't guess. Several
  rounds were lost to guessing.
- Tell me plainly when something is invented rather than ported. Energy
  Wars and Digi-Catch are original work, not ports, and so is anything
  new here.
- Verify in the simulator with screenshots before saying it works.

### Note on model

Most of this is mechanical — authoring data, following existing
patterns, build-and-screenshot loops. A lower reasoning setting is fine;
save the stronger model for design and awkward bugs.

---

## State at handoff

Build is green and the app runs. Working and verified: walking (tap and
shake), the cutscene queue with win/lose chains, exact transcriptions of
encounter / summon / battle turn / regular, spirit and Susanoomon
evolution, per-turn spirit power, audio with per-cutscene cues, all
screens free of text overlap, seven mini-games (five ported plus Energy
Wars and Digi-Catch as original work), triple-tap back on hold-controlled
mini-games.

Known gaps: Fusion and Ancient evolutions still reuse the spirit-
evolution scene; the Boost (DIGI-POWER) animations, the
`GameManager.cs` mini-game reward chains and the `TransitionToMap3`
endgame cutscene are not wired.

A colour screen was attempted twice and reverted both times — the
reasons are in the memory file. Don't re-open it without new artwork
that matches the game's own silhouettes.

Backup of the pre-colour monochrome build:
`../AppleWatch-backup-2026-07-31-monochrome/`
