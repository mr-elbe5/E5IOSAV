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
    
    func configurePhotoOutput() -> Bool {
        if isCaptureEnabled, let supportedMaxPhotoDimensions = currentDevice?.activeFormat.supportedMaxPhotoDimensions{
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
            return true
        }
        return false
    }
    
    func capturePhoto() -> Bool{
        if isCaptureEnabled, self.photoSettings != nil{
            let photoSettings = AVCapturePhotoSettings(from: self.photoSettings)
            if let videoRotationAngle = self.videoDeviceRotationCoordinator?.videoRotationAngleForHorizonLevelCapture{
                self.photoOutputReadinessCoordinator.startTrackingCaptureRequest(using: photoSettings)
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
                return true
            }
        }
        return false
    }
    
}

class PhotoCaptureProcessor: NSObject {
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    lazy var context = CIContext()
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    private var photoData: Data?
    
    var delegate: CameraDelegate? = nil
    var location: CLLocation?

    init(with requestedPhotoSettings: AVCapturePhotoSettings, completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.completionHandler = completionHandler
    }
    
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Log.error("Error capturing photo: \(error)")
            return
        }
        self.photoData = photo.fileDataRepresentation()
        if let location = location, let data = self.photoData{
            if let dataWithCoordinates = setImageProperties(data: data, altitude: location.altitude, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, utType: .jpeg){
                self.photoData = dataWithCoordinates
                
            }
        }
    }
    
    func setImageProperties(data: Data, dateTime: Date? = nil,
                                    offsetTime: String? = nil,
                                    altitude: Double? = nil,
                                    latitude: Double? = nil,
                                    longitude: Double? = nil,
                                    utType: UTType = .jpeg) -> Data?{
        if let src = CGImageSourceCreateWithData(data as CFData,  nil),
           let destData = CFDataCreateMutable(.none, 0),
           let dest: CGImageDestination = CGImageDestinationCreateWithData(destData, utType.identifier as CFString, 1, nil){
            let properties = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil)! as NSDictionary).mutableCopy() as! NSMutableDictionary
            if dateTime != nil || offsetTime != nil{
                var exifProperties: NSMutableDictionary
                if let  currentExifProperties = properties.value(forKey: kCGImagePropertyExifDictionary as String) as? NSMutableDictionary{
                    exifProperties = currentExifProperties
                }
                else{
                    exifProperties = NSMutableDictionary()
                    properties[kCGImagePropertyExifDictionary] = exifProperties
                }
                print(exifProperties)
                var iptcProperties: NSMutableDictionary
                if let  currentIptcProperties = properties.value(forKey: kCGImagePropertyIPTCDictionary as String) as? NSMutableDictionary{
                    iptcProperties = currentIptcProperties
                }
                else{
                    iptcProperties = NSMutableDictionary()
                    properties[kCGImagePropertyIPTCDictionary] = iptcProperties
                }
                if let dateTime = dateTime{
                    exifProperties[kCGImagePropertyExifDateTimeOriginal] = DateFormats.exifDateFormatter.string(for: dateTime)
                    exifProperties[kCGImagePropertyExifDateTimeDigitized] = DateFormats.exifDateFormatter.string(for: dateTime)
                    iptcProperties[kCGImagePropertyIPTCDateCreated] = DateFormats.iptcDateFormatter.string(for: dateTime)
                    iptcProperties[kCGImagePropertyIPTCTimeCreated] = DateFormats.iptcTimeFormatter.string(for: dateTime)
                    iptcProperties[kCGImagePropertyIPTCDigitalCreationDate] = DateFormats.iptcDateFormatter.string(for: dateTime)
                    iptcProperties[kCGImagePropertyIPTCDigitalCreationTime] = DateFormats.iptcTimeFormatter.string(for: dateTime)
                }
                if let offsetTime = offsetTime{
                    exifProperties[kCGImagePropertyExifOffsetTime] = offsetTime
                }
            }
            if altitude != nil || latitude != nil || longitude != nil{
                var gpsProperties: NSMutableDictionary
                if let  currentGpsProperties = properties.value(forKey: kCGImagePropertyGPSDictionary as String) as? NSMutableDictionary{
                    gpsProperties = currentGpsProperties
                }
                else{
                    gpsProperties = NSMutableDictionary()
                    properties[kCGImagePropertyGPSDictionary] = gpsProperties
                }
                if let altitude = altitude{
                    gpsProperties[kCGImagePropertyGPSAltitude] = altitude
                }
                if let latitude = latitude{
                    gpsProperties[kCGImagePropertyGPSLatitude] = latitude
                    gpsProperties[kCGImagePropertyGPSLatitudeRef] = latitude < 0 ? "S" : "N"
                }
                if var longitude = longitude{
                    if longitude > 180{
                        longitude -= 360
                    }
                    gpsProperties[kCGImagePropertyGPSLongitude] = abs(longitude)
                    gpsProperties[kCGImagePropertyGPSLongitudeRef] = longitude < 0 ? "W" : "E"
                }
            }
            print(properties)
            CGImageDestinationAddImageFromSource(dest, src, 0, properties)
            CGImageDestinationFinalize(dest)
            return destData as Data
        }
        return nil
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
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
            self.completionHandler(self)
        })
    }
}

