# Native clipboard workflow demo

[Watch the MP4](native-workflow.mp4) · [Animated GIF](native-workflow.gif)

The demo shows Marten's running native macOS application during scripted UI interactions:

1. Browse the clipboard history in **All Items**.
2. Open the **Work** pinboard, containing a reusable command snippet and sprint checklist.
3. Enter **S**, **Sp**, **Spri**, then **Sprint** and observe the history filter to the matching clip.

The video was encoded from successive app-window captures taken during these interactions. Frame timing follows the capture timestamps; it is a recording of the native interface, with no simulated controls or generated artwork. Recordly was not used for this media.

## Screenshots

| Screen | File |
| --- | --- |
| Horizontal clipboard history | [History](../screenshots/macos-history.jpg) |
| Horizontal Work pinboard | [Pinboard](../screenshots/macos-pinboard.jpg) |
| Horizontal search result | [Search](../screenshots/macos-search.jpg) |
| Compact clipboard history | [Compact history](../screenshots/macos-compact-history.jpg) |
| Compact Work pinboard | [Compact pinboard](../screenshots/macos-compact-pinboard.jpg) |
| Compact search result | [Compact search](../screenshots/macos-compact-search.jpg) |
| Native code clip editor | [Code editor](../screenshots/macos-code-editor.jpg) |

The capture build used the repository's application source with a separate sandboxed bundle identity and local store. The visible content came from the project's synthetic starter-data seeder. The capture host had no CloudKit entitlement. Application code was unchanged.

This demo covers history browsing, pinboards and live search. The editor is shown in a separate real screenshot. Cross-device sync, iOS and watchOS are documented from the source and are outside this recording's scope. Build and test results are recorded in the [development guide](../development.md).
