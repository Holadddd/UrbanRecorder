//
//  HomeMapViewModel.swift
//  UrbanRecorder
//
//  Created by ting hui wu on 2021/10/21.
//

import Foundation
import MapKit
import CoreLocation
import CoreMotion
import SwiftUI

class HomeMapViewModel: NSObject, ObservableObject {
    
    var buttonScale: CGFloat {
        return DeviceInfo.isCurrentDeviceIsPad ? 3 : 2
    }
    @Published var userID: String = ""
    
    @Published var recieverID: String = ""
    
    @Published var cardPosition = CardPosition.bottom
    
    var isUpdatedUserRegion: Bool = false
    
    var isMapDisplayFullScreen: Bool = true
    
    var urAudioEngineInstance = URAudioEngine.instance
    
    @Published var latitude: Double = 0
    
    @Published var longitude: Double = 0
    
    @Published var altitude: Double = 0
    
    private var firstAnchorMotion: CMDeviceMotion?
    
    var yaw: Double = 0
    
    var roll: Double = 0
    
    var pitch: Double = 0
    
    @Published var receiverLastDirectionDegrees: Double = 0
    
    @Published var receiverLastDistanceMeters: Double = 0
    
    @Published var isShowingRecorderView: Bool = false
    
    @Published var isSelectedItemPlayAble: Bool = false
    
    let locationManager = CLLocationManager()
    
    let headphoneMotionManager = CMHeadphoneMotionManager()
    
    var annotationItems: [HomeMapAnnotationItem] = [HomeMapAnnotationItem.taipei101]
    
    @Published var userCurrentRegion: MKCoordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.75773, longitude: -73.985708), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    
    var udpSocket: UDPSocketManager = UDPSocketManager.shared
    
    func updateUserCurrentRegion() {
        
    }
    override init() {
        super.init()
        // Delegate/DataSource
        urAudioEngineInstance.dataSource = self
        urAudioEngineInstance.delegate = self
        // Location
        locationManager.delegate = self
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        locationManager.requestWhenInUseAuthorization()
        
        locationManager.startUpdatingLocation()
        // Headphone Motion
        if headphoneMotionManager.isDeviceMotionAvailable {
            headphoneMotionManager.delegate = self
            
            headphoneMotionManager.startDeviceMotionUpdates(to: OperationQueue.current!, withHandler: {[weak self] motion, error  in
                guard let self = self, let motion = motion, error == nil else { return }
                self.headphoneMotionDidChange(motion)
            })
        }
    }
    
    func menuButtonDidClisked() {
        print("menuButtonDidClisked")
    }
    
    func recordButtonDidClicked() {
        print("recordButtonDidClicked")
        isShowingRecorderView.toggle()
    }
    
    func playButtonDidClicked() {
        print("playButtonDidClicked")
    }
    
    func getAvailableUsersList() {
        #warning("Test Api work for temporarily")
        HTTPClient.shared.request(UserAPI.getAvailableUsersList(userID: "")) { result in
            switch result {
            case .success(let data):
                guard let data = data, let list = try? JSONDecoder().decode(AvailableUserListRP.self, from: data) else {
                    print("Data is empty")
                    return
                }
                
                print(list)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func subscribeAllEvent() {
        SubscribeManager.shared.delegate = self
        
        SubscribeManager.shared.setupWith("test1234")
        
    }
    
    func startRecording(){
        urAudioEngineInstance.setupURAudioEngineCaptureCallBack {[weak self] audioData in
            guard let self = self else { return }
            // TODO: Send data through UDPSocket
            self.udpSocket.sendBufferData(audioData, from: self.userID, to: self.recieverID)
        }
    }
    
    func setupCallSessionChannel() {
        udpSocket.delegate = self
        udpSocket.setupConnection {[weak self] in
            guard let self = self else { return }
            self.startRecording()
        }
    }
}

extension HomeMapViewModel: UDPSocketManagerDelegate {
    func didReceiveAudioBuffersData(_ manager: UDPSocketManager, data: Data, from sendID: String) {
        let urAudioBuffer = URAudioEngine.parseURAudioBufferData(data)
        urAudioEngineInstance.schechuleRendererAudioBuffer(urAudioBuffer)
    }
}

extension HomeMapViewModel: SocketManagerDelegate {
    
    func callRequest(from user: UserInfo) {
        print("callRequest from: \(user)")
    }
    
    func callRequestAccept(from user: UserInfo) {
        print("callRequestAccept from: \(user)")
    }
    
    func callRequestDecline(from user: UserInfo) {
        print("callRequestDecline from: \(user)")
    }
    
    func calledSessionClosed(by user: UserInfo) {
        print("calledSessionClosed from: \(user)")
    }
    
}

// Core Data Manager
extension HomeMapViewModel: CLLocationManagerDelegate, CMHeadphoneMotionManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let altitude = location.altitude
        let locationCoordinate = CLLocationCoordinate2D(latitude: latitude,
                                                        longitude: longitude)
        DispatchQueue.main.async {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            
            if !self.isUpdatedUserRegion {
                self.userCurrentRegion.center = locationCoordinate
                self.isUpdatedUserRegion.toggle()
            }
        }
    }
    
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Did Fail With Error: \(error.localizedDescription)")
    }
    
    func headphoneMotionDidChange(_ motion: CMDeviceMotion) {
        guard let anchorMotion = firstAnchorMotion else { firstAnchorMotion = motion; return}
        
        yaw = motion.attitude.yaw - anchorMotion.attitude.yaw
        pitch = motion.attitude.pitch - anchorMotion.attitude.pitch
        roll = motion.attitude.roll - anchorMotion.attitude.roll
    }
}
// URAudioEngineDataSource
extension HomeMapViewModel: URAudioEngineDataSource {
    func urAudioEngine(currentLocationForEngine: URAudioEngine) -> URLocationCoordinate3D {
        let location = URLocationCoordinate3D(latitude: latitude, longitude: longitude, altitude: altitude)
        return location
    }
    
    func urAudioEngine(currentMotionForEngine: URAudioEngine) -> URMotionAttitude {
        let attitude = URMotionAttitude(roll: roll, pitch: pitch, yaw: yaw)
        return attitude
    }
}
// URAudioEngineDelegate
extension HomeMapViewModel: URAudioEngineDelegate {
    func didUpdateReceiverDirectionAndDistance(_ engine: URAudioEngine, directionAndDistance: UR2DDirectionAndDistance) {
        receiverLastDirectionDegrees = directionAndDistance.direction
        receiverLastDistanceMeters = directionAndDistance.distance
    }
}