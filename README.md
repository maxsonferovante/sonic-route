# Sonic Route

A native macOS menu bar utility for controlling each application's output volume, mute state, and audio destination independently. Requires macOS 26 or later.

Português: [README.pt-BR.md](README.pt-BR.md)

## Prototype status

The app discovers processes that are producing audio and uses Core Audio process taps to capture output for a bundle identifier. A local `AVAudioEngine` applies gain and sends the captured stream to the selected device. This uses public APIs rather than simulated per-app controls. macOS asks for system audio recording permission when capture starts.

Spotify and FaceTime are compatibility targets for live validation. Calls and physical audio devices were not available in this environment, so compatibility still needs validation on a Mac running Xcode with both apps producing audio.

## Requirements

- macOS 26 or later
- Xcode 26 to open and run `SonicRoute.xcodeproj`
- Swift 6.0 or later for Swift Package Manager commands

## Run

1. Open `SonicRoute.xcodeproj` in Xcode.
2. Select the **SonicRoute** scheme and run the app.
3. Click the waveform icon in the menu bar.
4. The first time you control an app, allow system audio recording under **System Settings → Privacy & Security**.

The app runs as a menu bar agent and does not appear in the Dock. For direct distribution, select a Developer ID signing team in Xcode and use Apple's archive and notarization workflow. This repository does not include a signed or notarized build.

## Tests

The unit tests use Swift Testing to cover volume rules, output fallback, app filtering, persistence by bundle identifier, and restoring controls when an app starts producing audio.

```sh
swift test
```

In Xcode, select the **SonicRoute** scheme and choose **Product → Test**.

## Architecture

- **MenuBarPanelView** and **ApplicationRowView** provide the compact SwiftUI panel, per-app controls, and loading, empty, and error states.
- **MenuBarViewModel** coordinates application rows, preferences, outputs, and periodic refreshes.
- **AudioDeviceServicing** enumerates output devices and identifies the system default.
- **AudioSessionServicing** discovers active audio processes and controls sessions by bundle identifier.
- **CoreAudioSessionService** creates a private process tap per app, aggregates the tap as an input, and routes it through `AVAudioEngine` to the selected device.
- **AppAudioPreferenceStore** persists volume, mute, and output choice by bundle identifier.
- Service protocols make rules and control state testable without physical audio hardware.

Audio stays in memory and is not recorded or sent over the network. Gain is applied by the local mixer. If a selected output disconnects, the app uses the macOS default and returns to the preferred output when it becomes available again.

## Permissions and known limitations

- The app declares `NSAudioCaptureUsageDescription`. Reading a process tap requires macOS consent for system audio recording. If consent is denied or a session cannot start, the app reports the error and leaves the original app without active routing.
- macOS provides no public setter for another app's volume or output device. The prototype mutes the original process while reading its tap and plays the captured stream; this can add latency.
- Compatibility varies by app, audio format, protected content, and device. Spotify and FaceTime need live testing before broad compatibility can be claimed.
- The app controls output audio. The macOS system continues to control the call microphone.
- System Sounds is omitted as an independent application because macOS does not document a stable process session with its own volume and mute controls.
- The first version does not install a virtual driver. Core Audio taps capture per-process output; a separate HAL driver would add privileged installation and is not required for this capture path.

## Project layout

```text
Sources/
  SonicRoute/       # app entry point and SwiftUI/AppKit views
  SonicRouteCore/   # models, rules, services, and view model
Tests/
  SonicRouteCoreTests/
```
