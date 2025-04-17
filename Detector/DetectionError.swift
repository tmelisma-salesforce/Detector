//
//  DetectionError.swift
//  Detector
//
//  Created by Toni Melisma on 4/16/25.
//

import Foundation // For Error, LocalizedError

/// Custom errors that can occur during the object detection process.
enum DetectionError: Error, LocalizedError {
    case modelNotLoaded
    case cgImageCreationFailed
    case imageLoadingFailed
    case detectionFailed(Error) // Wraps an underlying system error
    case unexpectedResultType
    case missingOutputFeature(String) // Includes the missing feature name
    case unexpectedOutputShape([Int]) // Includes the unexpected shape

    /// Provides user-friendly descriptions for each error case.
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The object detection model could not be loaded. Please ensure it's added to the app target."
        case .cgImageCreationFailed:
            return "Could not create a processable image format from the selected photo."
        case .imageLoadingFailed:
            return "Failed to load image data from the selected photo."
        case .detectionFailed(let underlyingError):
            // Provide more context from the underlying error if possible
            return "Object detection failed: \(underlyingError.localizedDescription)"
        case .unexpectedResultType:
             return "Received an unexpected result type from the detection model."
        case .missingOutputFeature(let name):
             return "Could not find the expected output feature '\(name)' in the model's results."
        case .unexpectedOutputShape(let shape):
             return "The model output tensor shape \(shape) did not match the expected shape."
        }
    }
}

