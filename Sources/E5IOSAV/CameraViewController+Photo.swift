/*
 E5Cam
 Simple Camera
 Copyright: Michael Rönnau mr@elbe5.de
 */

import UIKit
import AVFoundation
import CoreLocation
import Photos
import E5Data
import E5PhotoLib

extension CameraViewController{
    
    public func configurePhotoOutput() {
        if !isCaptureEnabled{
            return
        }
        let supportedMaxPhotoDimensions = currentDevice.activeFormat.supportedMaxPhotoDimensions
        if let largestDimension = supportedMaxPhotoDimensions.last{
            self.photoOutput.maxPhotoDimensions = largestDimension
        }
        self.photoOutput.isLivePhotoCaptureEnabled = false
        self.photoOutput.maxPhotoQualityPrioritization = .quality
        self.photoOutput.isResponsiveCaptureEnabled = self.photoOutput.isResponsiveCaptureSupported
        self.photoOutput.isFastCapturePrioritizationEnabled = self.photoOutput.isFastCapturePrioritizationSupported
        self.photoOutput.isAutoDeferredPhotoDeliveryEnabled = false
        let photoSettings = self.setUpPhotoSettings()
        DispatchQueue.main.async {
            self.photoSettings = photoSettings
        }
    }
    
    public func capturePhoto() {
        if !isCaptureEnabled{
            return
        }
        if self.photoSettings == nil {
            Log.error("No photo settings to capture")
            return
        }
        let photoSettings = AVCapturePhotoSettings(from: self.photoSettings)
        self.photoOutputReadinessCoordinator.startTrackingCaptureRequest(using: photoSettings)
        let videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelCapture
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoRotationAngle = videoRotationAngle
            }
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, completionHandler: { photoCaptureProcessor in
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            })
            photoCaptureProcessor.delegate = self.delegate
            photoCaptureProcessor.location = self.locationManager.location
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
            self.photoOutputReadinessCoordinator.stopTrackingCaptureRequest(using: photoSettings.uniqueID)
        }
    }
    
}

public class PhotoCaptureProcessor: NSObject {
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    lazy var context = CIContext()
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    private var photoData: Data?
    
    public var delegate: CameraDelegate? = nil
    public var location: CLLocation?

    public init(with requestedPhotoSettings: AVCapturePhotoSettings, completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.completionHandler = completionHandler
    }
    
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Log.error("Error capturing photo: \(error)")
            return
        }
        self.photoData = photo.fileDataRepresentation()
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            Log.error("Error capturing photo: \(error)")
            completionHandler(self)
            return
        }
        guard photoData != nil else {
            Log.error("No photo data resource")
            completionHandler(self)
            return
        }
        if let delegate = delegate{
            DispatchQueue.main.async{
                delegate.photoCaptured(data: self.photoData!, location: self.location)
            }
        }
        PhotoLibrary.savePhoto(photoData: self.photoData!, fileType: self.requestedPhotoSettings.processedFileType, location: self.location, resultHandler: { s in
            Log.debug("saved photo with locaIdentifier \(s)")
            self.completionHandler(self)
        })
    }
}

