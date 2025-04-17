//
//  ContentView.swift
//  Detector
//
//  Created by Toni Melisma on 4/16/25.
//

import SwiftUI
import PhotosUI // For PhotosPicker

struct ContentView: View {
    // State for the image picker
    @State private var selectedPhotoItem: PhotosPickerItem?
    // State for the original image displayed
    @State private var originalImage: Image?
    // State for the UIImage used for processing
    @State private var uiImageToProcess: UIImage?
    // State for storing FINAL detected objects after NMS
    @State private var finalDetections: [Detection] = []
    // State to indicate if processing is happening
    @State private var isProcessing: Bool = false
    // State to show error messages
    @State private var errorMessage: String?

    // Object detector instance (lives here or could be passed as EnvironmentObject)
    // Using @StateObject ensures it persists for the life of the view
    @StateObject private var objectDetector = ObjectDetector()

    var body: some View {
        NavigationStack {
            VStack {
                // Display Error Message
                if let errorMsg = errorMessage {
                    Text("Error: \(errorMsg)")
                        .foregroundColor(.red)
                        .padding()
                }

                // Image Display Area with Overlays
                ZStack {
                    if let displayImage = originalImage {
                        displayImage
                            .resizable()
                            .scaledToFit()
                            .overlay(
                                GeometryReader { geometry in
                                    Canvas { context, size in
                                        drawBoundingBoxes(
                                            detections: finalDetections, // Use final detections
                                            context: context,
                                            imageSize: geometry.size // Pass actual displayed size
                                        )
                                    }
                                }
                            )
                    } else {
                        Rectangle() // Placeholder
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(1.0, contentMode: .fit)
                            .overlay(Text("Select an Image"))
                    }

                    // Loading Indicator
                    if isProcessing {
                        ProgressView("Processing...")
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding(20)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(10)
                    }
                }
                .padding()

                Spacer() // Pushes button to the bottom

                // Photos Picker Button
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images, // Only allow images
                    photoLibrary: .shared() // Use the shared photo library
                ) {
                    Label("Select Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
                .disabled(isProcessing) // Disable while processing
            }
            .navigationTitle("YOLOv8 Object Detection")
            .navigationBarTitleDisplayMode(.inline)
            // Trigger processing when a new photo item is selected
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await processSelectedPhoto(item: newItem)
                }
            }
            // Handle detector setup errors
            .onAppear {
                 if let setupError = objectDetector.setupError {
                     errorMessage = setupError
                 }
            }
        }
    }

    // MARK: - Image Processing Logic

    private func processSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        print("[DEBUG ContentView] Starting photo processing...")

        // Reset state on main thread
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
            finalDetections = []
            originalImage = nil
            uiImageToProcess = nil
        }

        let startTime = Date()

        do {
            // Load image data from the selected item
            print("[DEBUG ContentView] Loading image data...")
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                throw DetectionError.imageLoadingFailed
            }
            print("[DEBUG ContentView] Image data loaded successfully.")

            // Update UI on main thread
            await MainActor.run {
                self.originalImage = Image(uiImage: uiImage)
                self.uiImageToProcess = uiImage
            }

            // Perform detection using the ObjectDetector instance
            guard let imageToProcess = uiImageToProcess else {
                throw DetectionError.imageLoadingFailed
            }

            print("[DEBUG ContentView] Starting object detection task...")
            let detections = try await objectDetector.performDetection(on: imageToProcess)
            let detectionEndTime = Date()
            print("[DEBUG ContentView] Object detection task finished in \(detectionEndTime.timeIntervalSince(startTime).formatted(.number.precision(.fractionLength(3))))s. Found \(detections.count) final detections after NMS.")


            // Update state with results on main thread
            await MainActor.run {
                self.finalDetections = detections
                print("[DEBUG ContentView] Updated UI with final detections.")
            }

        } catch {
            // Handle errors
            let errorTime = Date()
            print("[ERROR ContentView] Processing failed after \(errorTime.timeIntervalSince(startTime).formatted(.number.precision(.fractionLength(3))))s: \(error)")
            await MainActor.run {
                // Ensure error message reflects localized description if available
                if let localized = error as? LocalizedError {
                    errorMessage = localized.errorDescription ?? "An unknown error occurred."
                } else {
                    errorMessage = error.localizedDescription
                }
                originalImage = nil // Clear image on error
                uiImageToProcess = nil
            }
        }

        // Ensure processing indicator is turned off
        await MainActor.run {
            isProcessing = false
            print("[DEBUG ContentView] Finished photo processing.")
        }
    }

    // MARK: - Drawing Logic (SwiftUI Canvas)

    private func drawBoundingBoxes(detections: [Detection], context: GraphicsContext, imageSize: CGSize) {
        print("[DEBUG ContentView Canvas] Drawing: Received \(detections.count) detections. Image size: \(imageSize)")
        guard imageSize.width > 0, imageSize.height > 0 else {
            print("[DEBUG ContentView Canvas] Invalid image size, skipping draw.")
            return
        }

        let imageWidth = imageSize.width
        let imageHeight = imageSize.height

        for detection in detections {
            // 1. Get Normalized Bounding Box
            let normalizedRect = detection.box // Origin top-left

            // 2. Convert to Canvas Coordinates (scaling)
            let canvasRect = CGRect(
                x: normalizedRect.origin.x * imageWidth,
                y: normalizedRect.origin.y * imageHeight,
                width: normalizedRect.width * imageWidth,
                height: normalizedRect.height * imageHeight
            )

            // 3. Draw Bounding Box
            let rectPath = Path(roundedRect: canvasRect, cornerRadius: max(2, imageWidth / 200))
            context.stroke(rectPath, with: .color(.red), lineWidth: max(2, imageWidth / 300))

            // 4. Prepare and Draw Label
            let confidenceString = String(format: "%.2f", detection.confidence)
            let labelText = "\(detection.label ?? "ID:\(detection.classIndex)"): \(confidenceString)" // Use label getter

            // Calculate text properties
            let text = Text(labelText).font(.caption).bold().foregroundColor(.white)
            let resolvedText = context.resolve(text)
            let textSize = resolvedText.measure(in: CGSize(width: imageWidth, height: imageHeight))

            // Position text slightly above the box, ensuring it stays within bounds
            let textOriginX = max(0, canvasRect.minX + 2)
            let textOriginY = max(0, canvasRect.minY - textSize.height - 2)

            let textBackgroundRect = CGRect(
                origin: CGPoint(x: textOriginX - 2, y: textOriginY - 1),
                size: CGSize(width: textSize.width + 4, height: textSize.height + 2)
            )

            // Draw background and text
            context.fill(Path(textBackgroundRect), with: .color(.red.opacity(0.7)))
            context.draw(resolvedText, at: CGPoint(x: textOriginX, y: textOriginY), anchor: .topLeading)
        }
         print("[DEBUG ContentView Canvas] Drawing finished.")
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

