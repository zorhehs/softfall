<div align="center">

<img src="Resources/icon-1024.png" width="128" alt="Softfall">

# Softfall

**Weather for your desktop, and the sound that goes with it.**

A small menu bar app for macOS. Rain falls over your screen while you work,
clicks pass straight through, and every layer's picture and sound switch on
and off independently.

[![Build](https://github.com/zorhehs/softfall/actions/workflows/build.yml/badge.svg)](https://github.com/zorhehs/softfall/actions/workflows/build.yml)
&nbsp;·&nbsp; macOS 13+ &nbsp;·&nbsp; Universal (Apple silicon + Intel) &nbsp;·&nbsp; MIT

</div>

---

## Install

```sh
brew tap zorhehs/softfall https://github.com/zorhehs/softfall
brew install --cask softfall
```

Or grab the `.zip` from [Releases](https://github.com/zorhehs/softfall/releases),
unzip it, and drag `Softfall.app` to `/Applications`.

Softfall has no Dock icon. After installing, look for the cloud in your menu bar.

## What's in it

Ten layers. Each one has a picture switch, a sound switch, and one slider for
how much of it there is.

| | Layer | On screen | In your ears |
|---|---|---|---|
| 🌧 | **Rain** | Falling streaks, slanted by the breeze | Hiss, low roar, and individual drops |
| ❄️ | **Snow** | Drifting, tumbling flakes | The soft hush that comes with snowfall |
| 🌬 | **Breeze** | Faint motes carried sideways | Gusts that rise and fall, never on a loop |
| ⚡️ | **Thunder** | Lightning — flicker up close, bloom far off | Rumble, arriving *after* the flash |
| 🌫 | **Fog** | A slow haze that softens the edges | — |
| ✨ | **Fireflies** | Slow points of light, wandering | — |
| 🔥 | **Embers** | Sparks lifting off the bottom of the screen | Crackle over a fire's low roar |
| 🌊 | **Ocean** | — | Swell and retreat, three overlapping rhythms |
| 💧 | **Stream** | — | Water over stones, with bubbles |
| 〰️ | **Deep Hum** | — | A level low tone. Unreasonably good for focus |

Eight one-click scenes combine them: Quiet Rain, Downpour, Snowfall, Campfire,
Shoreline, Forest Stream, Deep Focus, Night Window.

## The sound is generated, not recorded

There are no audio files in this app. Every sound is synthesised in real time
from filtered noise, and that is a deliberate choice rather than a shortcut:

- **It never loops.** Sample-based ambience repeats every thirty seconds or so,
  and once you notice the seam you cannot un-notice it. There is no seam here.
- **It responds.** The rain slider does not just change the volume — it moves
  filter cutoffs, brings in a low roar, and thins out the individual droplets,
  the way rain actually behaves as it gets heavier.
- **The storm is one system.** Lightning is drawn first; the thunder is handed
  to the audio engine a moment later, and how long you wait is what your ear
  reads as distance. The breeze that bends the rain on screen is the same value
  that drives the gusts you hear.
- **It costs nothing to ship.** The whole app is a few hundred kilobytes.

## Built to be ignored

An ambient app earns its place by not competing for attention.

- **Click-through.** The overlay never takes focus and never intercepts a click,
  a scroll or a gesture.
- **It stays under your menus.** The overlay sits above your windows but below
  the menu bar, the Dock, and any menu you have open. Weather should not land
  on top of something you are trying to read.
- **Behind-windows mode.** Puts the weather on the desktop instead, so you only
  see it in the gaps around what you are actually doing. If motion over your
  work is too much, this is the setting you want.
- **It gets out of the way of full screen.** Turn on *Hide over full-screen
  apps* and films, presentations and full-screen editors are left alone.
- **Calm mode.** Fewer particles, slower movement, softer contrast.
- **It watches your battery.** On battery or in Low Power Mode, the animation
  stops and the sound carries on — sound is the cheap part. Visuals also stop
  when the display sleeps or the screen locks.
- **Sleep timer.** Fades out across the last two minutes rather than cutting
  off, so drifting off doesn't end with a click.
- **It won't show up in screen shares.** The overlay excludes itself from
  screen recording, so your rain stays yours.

Particles are drawn by Core Animation on the GPU, so leaving it running all day
is a reasonable thing to do.

## Build it yourself

```sh
git clone https://github.com/zorhehs/softfall.git
cd softfall
Scripts/build-app.sh
open dist/Softfall.app
```

There is no Xcode project — just a Swift package and one shell script that
assembles the bundle. Easier to read, easier to review, and it builds the same
way on a laptop and on CI.

```
Sources/Softfall
├── Audio/     DSP primitives, the synthesis voices, the AVAudioEngine host
├── Visual/    Click-through windows, Core Animation emitters, lightning
├── Core/      Layer model, saved state, presets, power awareness
└── UI/        Menu bar item and the SwiftUI control panel
```

## A note on Gatekeeper

Release builds are ad-hoc signed, not notarised — notarisation needs a paid
Apple Developer ID. The Homebrew cask clears the quarantine flag for you on
install, which is the same thing you would do by hand with right-click → Open.

If you install the `.zip` manually, macOS will refuse to open the app on first
launch. Either right-click it and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Softfall.app
```

Adding a `CODESIGN_IDENTITY` secret and a notarisation step to
`.github/workflows/release.yml` makes all of this unnecessary.

## Roadmap

Work in progress lives on [`develop`](../../tree/develop).

- Global hotkey to show and hide everything
- Save your own mixes as named scenes
- Duck automatically when a call starts or music plays
- Match your actual local weather, opt in
- Warm and dim the scene after sunset
- Per-display layer choices, not just on/off
- Honour the system *Reduce Motion* setting
- A gentle breathing pacer you can overlay

## License

MIT — see [LICENSE](LICENSE).
