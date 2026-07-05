# Shark Teeth AR

An iPhone prototype that points the camera at the ground, runs machine vision on
every frame, draws bounding boxes around shark teeth, and pins ("locks") a marker
in AR world space so the box stays put even when you move the phone.

## How it works

- **ARKit + RealityKit** run the camera and track the world.
- **Vision** runs a detector ~6 times a second on camera frames.
- Live detections get a **yellow 2D bounding box** that follows the object.
- When a detection stays put for a few frames, the app raycasts into the world
  and **locks a yellow square marker** onto the real surface. It stays anchored
  there as you move around.

### Demo mode vs. real model

There is no built-in "shark tooth" detector in iOS, so the app has two modes:

- **Demo mode (default):** uses Apple's generic *salient object* detector, which
  boxes anything that visually stands out. This proves the whole
  camera → detection → box → AR-lock pipeline works before any training.
- **Real model:** train an *Object Detection* model in Apple's free **Create ML**
  app (comes with Xcode: `Xcode → Open Developer Tool → Create ML`) using photos
  of shark teeth with labeled rectangles. Export it as `SharkToothDetector.mlmodel`,
  drop the file into the `SharkToothAR/` folder, re-run `xcodegen generate`, and
  rebuild. The app picks it up automatically — the status bar at the top tells
  you which mode is active.

## Building and running (first time)

The Xcode project file is generated from `project.yml`:

```sh
brew install xcodegen   # already installed if Claude set this up
xcodegen generate
open SharkToothAR.xcodeproj
```

ARKit needs a real camera, so this **must run on a physical iPhone** (the
simulator won't work):

1. In Xcode, click the project (blue icon, top of left sidebar) → the
   **SharkToothAR** target → **Signing & Capabilities** tab.
2. Under **Team**, pick your Apple ID (add it via `Xcode → Settings → Accounts`
   if it's not there — a free account works).
3. Plug in your iPhone with a cable and pick it in the device menu at the top
   of the window.
4. On the phone, enable **Settings → Privacy & Security → Developer Mode**
   (appears after the first install attempt; requires a restart).
5. Press **⌘R**. The first run, the phone will ask you to trust your developer
   certificate: **Settings → General → VPN & Device Management**.

Point the camera at objects on a table or the ground. Yellow boxes track
detections live; after ~1 second on the same spot, a square marker locks onto
the surface and stays there.

## Project layout

```
project.yml                      # xcodegen config → generates the .xcodeproj
SharkToothAR/
  SharkToothARApp.swift          # app entry point
  ContentView.swift              # camera + overlay + status UI
  ARViewContainer.swift          # ARKit session, frame throttling, AR locking
  ToothDetector.swift            # Vision pipeline (Core ML model or demo fallback)
  DetectionOverlayView.swift     # draws the live 2D bounding boxes
  AppState.swift                 # shared state between AR session and UI
```
