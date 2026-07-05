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

### The detection model

The app ships with `SharkToothAR/SharkToothDetector.mlpackage`, a YOLOv8-nano
detector fine-tuned on the open [RF100 shark-teeth dataset](https://universe.roboflow.com/roboflow-100/shark-teeth-5atku)
(280 images of fossil teeth, CC license, via its
[Hugging Face mirror](https://huggingface.co/datasets/Francesco/shark-teeth-5atku)).
Validation results: 99.6% precision, 100% recall, 0.995 mAP@50. It was exported
to Core ML with a built-in NMS pipeline, so Vision returns ready-to-use labeled
boxes. The status bar shows "Shark tooth model loaded" when it's active.

**Expectation setting:** the training photos are museum-style specimens (clean
tooth, plain background), so it works best on a tooth on a table or in your
hand. A tooth half-buried in shell hash will be hit-or-miss until the model is
retrained with real beach photos.

If the model file is ever removed, the app falls back to Apple's generic
*salient object* detector (labeled "demo mode" in the status bar) so the
AR pipeline still works.

### Retraining: one command

```sh
./training/retrain.sh
```

That single command does everything: creates the Python environment if needed
(one-time, ~2 GB download), fetches the RF100 dataset, fine-tunes the model on
the Mac's GPU, exports to Core ML, installs the result as
`SharkToothAR/SharkToothDetector.mlpackage`, and regenerates the Xcode project.
When it says "Done", open Xcode and press ⌘R — the next build uses the new model.

To train on **your own photos** (the big accuracy win for beach conditions):
label them in YOLO format (Roboflow or Label Studio make this easy — draw a
rectangle around each tooth), then:

```sh
./training/retrain.sh path/to/your/data.yaml
```

Options via environment variables, e.g. `EPOCHS=120 ./training/retrain.sh`:

| Variable | Default | Meaning |
|----------|---------|---------|
| `EPOCHS` | 80 | training epochs |
| `IMGSZ`  | 640 | training image size |
| `BASE`   | `training/best.pt` | weights to start from |

### Improving accuracy (false positives / missed teeth)

Field testing shows the current model both false-alarms on tooth-shaped debris
and misses real teeth. That's the expected *domain gap*: it was trained on
museum photos (one clean tooth, large in frame, plain background), so it never
learned what shells and rocks look like, and real teeth in clutter look nothing
like its training data. Both error types at once means threshold tuning can't
fix it — raising the bar trades misses for false alarms and vice versa. Only
better training data fixes it. In order of impact:

1. **Labeled beach photos (~50–150).** Shoot teeth with the iPhone in real
   hunting conditions: on sand, in shell hash, on gravel, wet and dry, varied
   distance and light. Draw a box around each tooth (Roboflow or Label Studio,
   free tiers, YOLO export format), then run
   `./training/retrain.sh path/to/data.yaml`.
2. **Hard negatives — nearly free.** Photos of beach ground with *no* teeth
   (the shells and rocks currently fooling it) need no labeling: add them to
   the training images with empty label files and the model learns "not a
   tooth." Even 30–50 of these noticeably cuts false positives.
3. **Get closer.** The model saw large-in-frame teeth in training, so hold the
   phone 8–20 inches from the ground. Small, distant teeth will be missed
   regardless of training.

App-side knobs (in `SharkToothAR/ToothDetector.swift` and
`ARViewContainer.swift`): the per-detection confidence cutoff (default 0.5)
and the streak length before a marker locks (default 4 passes). These trade
off false pins against responsiveness but can't fix the underlying model.

What's in `training/`:

- `retrain.sh` — the one-command pipeline described above
- `best.pt` — current trained weights; each retrain updates this and keeps the
  previous version as `best.prev.pt` (set `BASE=training/best.prev.pt` to roll back)
- `coco_to_yolo.py` — converts the RF100 COCO download to YOLO format
- `export_coreml.py` — exports any `.pt` weights to Vision-compatible Core ML
- `results.png`, `val_batch0_pred.jpg` — training curves and sample predictions
- `venv/`, `work/` — environment and scratch space the script manages (gitignored)

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
  SharkToothDetector.mlpackage   # trained YOLOv8n shark tooth model (Core ML)
  Assets.xcassets/               # app icon
training/                        # trained weights + scripts to retrain/export
design/icon.svg                  # editable app icon source
```
