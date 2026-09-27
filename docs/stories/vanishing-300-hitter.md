# The vanishing .300 hitter

Native, offline MLB story, available through the global Stories button between the team selector and playoffs. The global library also links to the existing Boston, Milwaukee and Yankees stories. Team Stories pages keep their existing team-specific content.

## Definition and provenance

`MLB300HitterData.swift` reproduces the exact 50-season series supplied in the user's Hub Ball handoff. It is an editorial input, not an independently recomputed MLB data extract. The methodology sheet says so. The threshold is officially displayed AVG >= .301, not .300-or-better; the supplied series ends at six in 2025 and peaks at 51 in 1999. The 2026 YTD point is a separately verified MLB Stats API snapshot: six qualified hitters displayed at .301 or higher, checked before September 27 games. The current 88% decline uses that provisional endpoint. The dated player totals and retrieval URL are saved in `mlb300-2026-snapshot.json`.

Qualification follows the handoff's 3.1 PA per team game rule, accounting for actual season length. Shortened seasons remain in the series. The historical reconstruction formula in the handoff is PA = AB + BB + HBP + SH + SF. Before recalculating or extending the series, preserve a player-level source extract and reconcile qualification and rounding with official MLB totals, including traded-player aggregation and any qualification exceptions. Do not substitute a fixed 502-PA minimum for shortened seasons and always distinguish unfinished 2026 from final historical totals.

## Components

- `MLB300HitterStory.swift`: full-screen presentation, launch overlay, stat cards, native vector chart, inspector, controls and methodology.
- `MLB300HitterData.swift`: dedicated season module and timing functions.
- `StoryAudioController.swift` / `StoryAudioLoop.swift`: locally synthesized ambient pad as an in-memory PCM WAV through AVAudioPlayer; no downloads or third-party services.
- `StoriesView.swift`: optional team scope; nil shows the global library.

The primary path trims from zero to one over 10 seconds using monotonic elapsed time. The build shows only the line, with no year dots. Once complete, markers highlight the peak, final year, and tapped year. Reduced Motion reveals the completed chart immediately. Replay resets the clock without stacking audio players. Music defaults off and can start only in response to a launch or music-button tap. It respects silent mode, mixes with other audio, and stops on interruption, dismissal or backgrounding. Returning to the app shows the completed chart without automatically restarting sound.

Every year can be selected by tapping its x-position or hovering, with a discrete Season slider for fine selection and VoiceOver. All values are also available in the methodology list. Long content scrolls at larger Dynamic Type sizes.

## Verification

Run `bash scripts/test_hitter_story_data.sh` for series invariants, boundary timing, and decoding the generated eight-second WAV (sample count, amplitude and loop seam).

Run the existing native UI harness with these methods:

```sh
bash scripts/test_large_text_ui.sh SIMULATOR_UUID hitter-story \
  testHitterStoryPlaybackAndAllSeasons \
  testHitterStoryGlobalNavigation \
  testHitterStoryLargeText \
  testHitterSoundLifecycleAndCompactHeader \
  testHitterAudiblePlayback
```

Debug routes: `-show-hitter-story` and `-show-story-library`.

## Future seasons

The user authorized including 2026 before the final games on September 27. It is explicitly marked YTD in the card, axis, endpoint callout, year inspector, accessibility descriptions and methodology. The chart retains 2025’s final six, then adds 2026’s provisional six. The ending is “Six so far. Will it end at six again?”

After the last games, fetch official qualified season totals again, apply the displayed AVG >= .301 cutoff, and update the count if needed. Only then remove the provisional flag and revise the snapshot date, narrative, question, methodology and tests to final-season wording. This snapshot does not refresh automatically.

## Audio verification limitation

The current Mac uses a Jump Desktop virtual default audio output. Both AVAudioEngine and AVAudioPlayer startup were rejected in the iOS simulator. The WAV itself successfully decodes through AVAudioFile. The UI tests assert the visible silent fallback and continue testing the story; the distinct audible-playback check explicitly skips when the route is unavailable. Audible music on a working simulator route or physical device remains a release check. No Mac sound settings were changed.

## Verified in this implementation

- iPhone 17 Pro simulator: global navigation, full-screen launch/dismiss, year-by-year taps against the supplied counts (extended to 51 points for the dated 2026 snapshot), ten-second completion, replay, methodology sheet, and largest Dynamic Type layout.
- Compact iPhone simulator: largest-text header with the Diamondbacks label, launch with optional music enabled, graceful audio fallback, background/return behavior, and on-chart year selection.
- Swift checks: season continuity, endpoints, peak, decline, timing boundaries, point fade completion and generated WAV decoding.
- Audible playback test: explicitly skipped because the simulator audio route rejected playback. This is not an audio-output pass.

UI evidence is generated under `dist/hitter-preview/` and result bundles under `dist/large-text-ui/`; neither directory is committed. This change is a development implementation, not a device installation or TestFlight release.
