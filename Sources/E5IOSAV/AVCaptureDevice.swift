/*
 Common Basics
 Base classes and extension for IOS and MacOS
 Copyright: Michael Rönnau mr@elbe5.de
 */

import Foundation
import Photos
import E5Data

extension AVCaptureDevice {
    
    public static func askCameraAuthorization(callback: @escaping (Result<Void, Error>) -> Void){
        switch AVCaptureDevice.authorizationStatus(for: .video){
        case .authorized:
            callback(.success(()))
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video){ granted in
                if granted{
                    callback(.success(()))
                }
                else{
                    callback(.failure(GenericError("notAutorized")))
                }
            }
            break
        default:
            callback(.failure(GenericError("notAutorized")))
            break
        }
    }
    
    public static func askAudioAuthorization(callback: @escaping (Result<Void, Error>) -> Void){
        switch AVCaptureDevice.authorizationStatus(for: .audio){
        case .authorized:
            callback(.success(()))
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio){ granted in
                if granted{
                    callback(.success(()))
                }
                else{
                    callback(.failure(GenericError("notAutorized")))
                }
            }
            break
        default:
            callback(.failure(GenericError("notAutorized")))
            break
        }
    }
    
    public static func askVideoAuthorization(callback: @escaping (Result<Void, Error>) -> Void){
        askCameraAuthorization(){ result  in
            switch result{
            case .success(()):
                askAudioAuthorization(){ _ in
                    callback(.success(()))
                }
                return
            case .failure:
                callback(.failure(GenericError("notAutorized")))
                return
            }
        }
    }
    
}

