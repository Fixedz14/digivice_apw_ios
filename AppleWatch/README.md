# D-Tector for Apple Watch

Native watchOS port of the Unity 2019 D-Tector project in the parent directory.

## Source of truth

- Game version: `0.20.0513a`
- Virtual display: `32 × 32` pixels
- Apple Watch input mapping:
  - tap the left or right third of the screen for the original arrow inputs
  - tap the center/character for the original confirm input or a walking step
  - shake the watch for a walking step
  - hold anywhere for 0.48 seconds for the original back input
- The game face fills the watch display and has no visible SwiftUI buttons
- Game data, sprites, maps, and audio used by the current target live under
  `FullTouch/Resources`

## Generate and build

```sh
xcodegen generate --spec AppleWatch/project.yml --project AppleWatch
xcodebuild \
  -project AppleWatch/DTectorWatch.xcodeproj \
  -scheme DTectorWatch \
  -sdk watchos \
  -configuration Debug \
  -derivedDataPath /tmp/DTectorDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To install on a physical watch, open `DTectorWatch.xcodeproj`, select the
paired Apple Watch, keep the watch unlocked and near the Mac, then Run. The
project is configured for Apple Developer team `S7J4D76JRY`.

The current Unity source starts a new game immediately after character
selection. It contains no player-name field or name-entry flow, so the watch
port intentionally does not invent one.

The resource files are copied into the app bundle from `FullTouch/Resources`.
