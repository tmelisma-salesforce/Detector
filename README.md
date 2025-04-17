# Detector

A simple iOS SwiftUI object detection app using the Vision framework (iOS 18+) and a YOLOv11x Core ML model (with embedded NMS) to identify objects in user-selected photos and display bounding boxes with labels.

## Prerequisites

* macOS with Xcode 16 or later (required for iOS 18 SDK).
* An iOS device or simulator running iOS 18 or later.
* An Apple Developer account may be required to run on a physical device.
* A Python environment (e.g., venv) with `pip`.

## Setup

### 1. Obtain and Convert Model

The app requires a Core ML model file (`yolo11x.mlpackage`) which you need to generate from the original PyTorch model.

1.  **Download Model:** Download the `yolo11x.pt` weights file from the official Ultralytics repository/website (e.g., check models linked from [https://github.com/ultralytics/ultralytics](https://github.com/ultralytics/ultralytics)).
2.  **Create Environment:** Create and activate a Python virtual environment:
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    ```
3.  **Install Ultralytics:**
    ```bash
    pip install ultralytics
    ```
4.  **Export Model:** Navigate to the directory containing the downloaded `yolo11x.pt` file and run the export command:
    ```bash
    # Ensure you use the correct model weights filename
    yolo export model=yolo11x.pt format=coreml nms=true
    ```
    This will generate a `yolo11x.mlpackage` directory.
5.  **Add to Xcode:** Drag the entire `yolo11x.mlpackage` directory into your Xcode project navigator. Ensure it is added to the "Detector" app target when prompted (check Target Membership in the File Inspector).

### 2. Build and Run App

1.  Open the `Detector.xcodeproj` (or `.xcworkspace`) file in Xcode.
2.  Select your target device or simulator (must support iOS 18+).
3.  Build and run the app (Product > Run or Cmd+R).
4.  Tap "Select Photo" to choose an image for object detection.

## Copyright

Copyright (c) 2025 Toni Melisma

