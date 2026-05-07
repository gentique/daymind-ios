# Daymind

Daymind is a hackathon project built as part of the iOSKonf26 conference. It is an iOS prototype for recording conversations, generating an on-device transcript, and turning that transcript into a compact summary with key details.

The app is intentionally scoped like a conference hackathon build: it demonstrates the core workflow end to end, keeps data local, and leaves production hardening for later.

## What it does

- Records audio from sessions started by the user.
- Uses Apple's Speech framework for on-device live transcription.
- Uses Foundation Models / Apple Intelligence to update a summary and key details as the conversation develops.
- Saves sessions locally as JSON in Application Support.
- Shows previous sessions in a read-only history list.
- Includes a RevenueCat paywall integration path for subscription experiments.

## Requirements

- Xcode 26.3 or newer.
- iOS 26.2 SDK / deployment target.
- A physical iOS device with microphone and on-device speech recognition support.
- Apple Intelligence enabled on a supported device for generated summaries and key details.
- Network access when Xcode resolves Swift Package Manager dependencies.

The app requests microphone and speech recognition permissions at runtime. Background audio mode is enabled so active recording can continue when the app moves to the background.

## Dependencies

The project uses Swift Package Manager through Xcode:

- `RevenueCat`
- `RevenueCatUI`

RevenueCat is configured with a test API key in `DaymindApp.swift`. Replace it before using the paywall flow outside this prototype context.

## Running the app

1. Open `Daymind.xcodeproj` in Xcode.
2. Let Xcode resolve Swift Package Manager dependencies.
3. Select the `Daymind` scheme.
4. Choose a supported physical iOS device.
5. Build and run.
6. Grant microphone and speech recognition permissions when prompted.

You can also check that the app builds from the command line:

```sh
xcodebuild -project Daymind.xcodeproj \
  -scheme Daymind \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daymind-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Project structure

- `Daymind/ContentView.swift`: SwiftUI navigation, session list, recording screen, saved-session screen, and paywall entry point.
- `Daymind/ConversationViewModel.swift`: Recording state, transcript updates, and summary scheduling.
- `Daymind/SpeechTranscriber.swift`: Microphone setup and on-device speech recognition.
- `Daymind/ConversationSummarizer.swift`: Foundation Models integration for summaries and key details.
- `Daymind/SessionStore.swift`: Local JSON persistence for saved sessions.
- `Daymind/ConversationSession.swift`: Saved session model and title generation.

## Prototype notes

- Session data is stored locally and is not synced.
- Summary generation depends on Apple Intelligence availability.
- The current RevenueCat setup is for experimentation, not production distribution.
- There is no dedicated automated test target yet.
