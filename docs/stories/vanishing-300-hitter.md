# The vanishing .300 hitter

Native, offline MLB story, available through the global Stories button between the team selector and playoffs. The global library also links to the existing Boston, Milwaukee and Yankees stories. Team Stories pages keep their existing team-specific content.

## Definition and provenance

`MLB300HitterData.swift` contains generated counts from MLB’s qualified-hitter season totals. The cutoff is officially displayed AVG >= .300, **including exactly .300**. Every year was recalculated from MLB Stats API on September 27, 2026; the original .301+ handoff is superseded. The peak is 55 in 1999. Both 2025 and 2026 YTD have seven, a rounded 87% decline from the peak. 2024 also had seven.

Run `python3 scripts/fetch_hitter_story.py` to refresh all 51 years. It saves source URLs, retrieval time, displayed averages, hits, at-bats and plate appearances for every qualified player in `data/mlb300-hitters.json`, then regenerates the Swift season array. Requests must all succeed, with complete leaderboards and unique player IDs, before output is written. Review the snapshot label and story copy after each refresh; the app does not fetch or update this data automatically.

Qualification uses MLB’s `playerPool=QUALIFIED` rather than a fixed 502-PA cutoff. This preserves MLB’s treatment of shortened seasons and batting-title exceptions. MLB’s combined season totals count each traded player once. Use the displayed average, not an unrounded H/AB comparison: a displayed .300 qualifies even if its underlying fraction is slightly lower.

## Components

- `MLB300HitterStory.swift`: full-screen presentation, launch overlay, stat cards, native vector chart, inspector, controls and methodology.
- `MLB300HitterData.swift`: dedicated season module and timing functions.
- `StoryAudioController.swift` / `StoryAudioLoop.swift`: locally synthesized ambient pad as an in-memory PCM WAV through AVAudioPlayer; no downloads or third-party services.
- `StoriesView.swift`: optional team scope; nil shows the global library.

The primary path trims from zero to one over 10 seconds using monotonic elapsed time. The build shows only the line, with no year dots. Once complete, markers highlight the peak, final year, and tapped year. Reduced Motion reveals the completed chart immediately. Replay resets the clock without stacking audio players. Music defaults off and can start only in response to a launch or music-button tap. It respects silent mode, mixes with other audio, and stops on interruption, dismissal or backgrounding. Returning to the app shows the completed chart without automatically restarting sound.

Every year can be selected by tapping its x-position or hovering, with a discrete Season slider for fine selection and VoiceOver. All values are also available in the methodology list. Long content scrolls at larger Dynamic Type sizes.

## Verification

Run `python3 scripts/test_hitter_story_source.py` to check the inclusive cutoff, complete/unique source rows, and reconciliation of all 51 counts. Run `bash scripts/test_hitter_story_data.sh` for series invariants, boundary timing, and decoding the generated eight-second WAV (sample count, amplitude and loop seam).

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

The user authorized including 2026 before the final games on September 27. It is explicitly marked YTD in the card, axis, endpoint callout, year inspector, accessibility descriptions and methodology. The chart retains 2025’s final seven, then adds 2026’s provisional seven. The ending is “Seven so far. Will it end at seven again?”

After the last games, fetch official qualified season totals again, apply the displayed AVG >= .300 cutoff, and update the count if needed. Only then remove the provisional flag and revise the snapshot date, narrative, question, methodology and tests to final-season wording. This snapshot does not refresh automatically.

## Audio verification limitation

The current Mac uses a Jump Desktop virtual default audio output. Both AVAudioEngine and AVAudioPlayer startup were rejected in the iOS simulator. The WAV itself successfully decodes through AVAudioFile. The UI tests assert the visible silent fallback and continue testing the story; the distinct audible-playback check explicitly skips when the route is unavailable. Audible music on a working simulator route or physical device remains a release check. No Mac sound settings were changed.

## Verified in this implementation

- iPhone 17 Pro simulator: global navigation, full-screen launch/dismiss, year-by-year taps against the MLB-derived counts (extended to 51 points for the dated 2026 snapshot), ten-second completion, replay, methodology sheet, and largest Dynamic Type layout.
- Compact iPhone simulator: largest-text header with the Diamondbacks label, launch with optional music enabled, graceful audio fallback, background/return behavior, and on-chart year selection.
- Swift checks: season continuity, endpoints, peak, decline, timing boundaries, generated WAV decoding.
- Audible playback test: explicitly skipped because the simulator audio route rejected playback. This is not an audio-output pass.

UI evidence is generated under `dist/hitter-preview/` and result bundles under `dist/large-text-ui/`; neither directory is committed. This change is a development implementation, not a device installation or TestFlight release.
