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
    @Published var subscribeID: String = ""
    
    var currentSubscribeID: String = ""
    
    @Published var broadcastID: String = ""
    
    var currentBroadcastID: String = ""
    
    @Published var cardPosition = CardPosition.middle
    
    var isUpdatedUserRegion: Bool = false
    
    var isMapDisplayFullScreen: Bool = true
    
    var urAudioEngineInstance = URAudioEngine.instance
    
    @Published var latitude: Double = 0
    
    @Published var longitude: Double = 0
    
    @Published var altitude: Double = 0
    
    private var firstAnchorMotion: CMDeviceMotion?
    
    private var firstAnchorMotionCompassDegrees: Double?
    
    var trueNorthYawDegrees: Double = 0
    
    var trueNorthRollDegrees: Double = 0
    
    var trueNorthPitchDegrees: Double = 0
    
    var receiverDirection: Double {
        return compassDegrees + receiverLastDirectionDegrees
    }
    // TrueNorthOrientationAnchor(Assume the first motion is faceing the phone)
    var trueNorthMotionAnchor: CMDeviceMotion?
    
    @Published var compassDegrees: Double = 0
    
    var receiverLatitude: Double = 0
    
    var receiverLongitude: Double = 0
    
    var receiverAltitude: Double = 0
    
    @Published var receiverLastDirectionDegrees: Double = 0
    
    @Published var receiverLastDistanceMeters: Double = 0
    
    @Published var isShowingRecorderView: Bool = false
    
    @Published var isSelectedItemPlayAble: Bool = false
    
    var udpsocketLatenctMs: UInt64 = 0
    
    let locationManager = CLLocationManager()
    
    let headphoneMotionManager = CMHeadphoneMotionManager()
    
    var annotationItems: [HomeMapAnnotationItem] {
        var tmp: [HomeMapAnnotationItem] = []
        
        tmp.append(receiverAnnotationItem)
        
        return tmp
    }
    
    var receiverAnnotationItem: HomeMapAnnotationItem = HomeMapAnnotationItem(coordinate: CLLocationCoordinate2D(), type: .user, color: .clear)
    
    @Published var userCurrentRegion: MKCoordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.75773, longitude: -73.985708), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    
    var udpSocketManager: UDPSocketManager = UDPSocketManager.shared
    
    @Published var showWave: Bool = false
    
    var volumeMaxPeakPercentage: Double = 0.01
    
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
        
        if CLLocationManager.headingAvailable() {
            self.locationManager.startUpdatingHeading()
        }
        // Headphone Motion
        if headphoneMotionManager.isDeviceMotionAvailable {
            headphoneMotionManager.delegate = self
            
            headphoneMotionManager.startDeviceMotionUpdates(to: OperationQueue.current!, withHandler: {[weak self] motion, error  in
                guard let self = self, let motion = motion, error == nil else { return }
                self.headphoneMotionDidChange(motion)
            })
        }
        
        udpSocketManager.delegate = self
        
        // add UDPSocket latency
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleUDPSocketConnectionLatency),
                                               name: Notification.Name.UDPSocketConnectionLatency,
                                               object: nil)
        
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
    
    func subscribeChannel() {
        currentSubscribeID = subscribeID
        
        // 1. setupSubscribeEnviriment
        self.urAudioEngineInstance.setupAudioEngineEnvironmentForSubscribe()
        
        self.udpSocketManager.setupSubscribeConnection {
            self.udpSocketManager.subscribeChannel(from: "", with: self.currentSubscribeID)
        }
    }
    
    private func setupMicrophoneCaptureCallback(){
        urAudioEngineInstance.setupURAudioEngineCaptureCallBack {[weak self] audioData in
            guard let self = self else { return }
            // TODO: Send data through UDPSocket
            self.udpSocketManager.broadcastBufferData(audioData, from: "", to: self.currentBroadcastID)
        }
    }
    
    func broadcastChannel() {
        currentBroadcastID = broadcastID
        
        // 1. Request Microphone
        urAudioEngineInstance.requestRecordPermissionAndStartTappingMicrophone {[weak self] isGranted in
            guard let self = self else { return }
            if isGranted {
                // 2. setupBroadcastEnviriment
                self.urAudioEngineInstance.setupAudioEngineEnvironmentForBroadcast()
                // 3. Connect and send audio buffer
                self.udpSocketManager.setupBroadcastConnection {
                    self.setupMicrophoneCaptureCallback()
                }
            } else {
                print("Show Alert View")
                // TODO: Show Alert View
            }
        }
        
    }
    
    func didReceiveVolumePeakPercentage(_ percentage: Double) {
        // Vivration is not working
        UIDevice.vibrate()
        withAnimation(.linear(duration: 0.4)) {
            showWave = true
            
            volumeMaxPeakPercentage = percentage
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.resetVolumePeakPercentage()
        }
    }
    
    func resetVolumePeakPercentage() {
        showWave = false
        
        volumeMaxPeakPercentage = 0.01
    }
    
    func resetAnchorDegrees() {
        firstAnchorMotionCompassDegrees = nil
        firstAnchorMotion = nil
    }
    
    @objc func handleUDPSocketConnectionLatency(notification: Notification) {
        guard let msSecond = notification.userInfo?["millisecond"] as? UInt64 else { return }
        udpsocketLatenctMs = msSecond
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var newDegrees =  -newHeading.magneticHeading + 360
        
        if (newDegrees - compassDegrees) > 0 {
            if abs(newDegrees - compassDegrees) > 180 {
                newDegrees -= 360
            }
        } else {
            if abs(newDegrees - compassDegrees) > 180 {
                newDegrees += 360
            }
        }
        
        compassDegrees = newDegrees
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Did Fail With Error: \(error.localizedDescription)")
    }
    
    func headphoneMotionDidChange(_ motion: CMDeviceMotion) {
        guard let anchorMotion = firstAnchorMotion,
              let firstAnchorMotionCompassDegrees = firstAnchorMotionCompassDegrees else {
            firstAnchorMotionCompassDegrees = compassDegrees
            firstAnchorMotion = motion
            return}
        
        trueNorthYawDegrees = (anchorMotion.attitude.yaw - motion.attitude.yaw) / Double.pi * 180 - firstAnchorMotionCompassDegrees
        trueNorthPitchDegrees = (anchorMotion.attitude.pitch - motion.attitude.pitch) / Double.pi * 180
        trueNorthRollDegrees = (anchorMotion.attitude.roll - motion.attitude.roll) / Double.pi * 180
        
    }
}
// URAudioEngineDataSource
extension HomeMapViewModel: URAudioEngineDataSource {
    func urAudioEngine(currentLocationForEngine: URAudioEngine) -> URLocationCoordinate3D {
        let location = URLocationCoordinate3D(latitude: latitude, longitude: longitude, altitude: altitude)
        return location
    }
    
    func urAudioEngine(currentTrueNorthAnchorsMotionForEngine: URAudioEngine) -> URMotionAttitude {
        let attitude = URMotionAttitude(rollDegrees: trueNorthRollDegrees, pitchDegrees: trueNorthPitchDegrees, yawDegrees: trueNorthYawDegrees)
        return attitude
    }
}
// URAudioEngineDelegate
extension HomeMapViewModel: URAudioEngineDelegate {
    func didUpdateReceiversBufferMetaData(_ engine: URAudioEngine, metaData: URAudioBufferMetadata) {
        receiverLatitude = metaData.locationCoordinate.latitude
        receiverLongitude = metaData.locationCoordinate.longitude
        receiverAltitude = metaData.locationCoordinate.altitude
        
        // Update Receiver Location
        if receiverAnnotationItem.color == .clear {
            receiverAnnotationItem = HomeMapAnnotationItem(coordinate: CLLocationCoordinate2D(latitude: receiverLatitude, longitude: receiverLongitude),
                                                           type: .user, color: .orange)
        } else {
            receiverAnnotationItem.coordinate.latitude = receiverLatitude
            receiverAnnotationItem.coordinate.longitude = receiverLongitude
        }
        
        let userLocation = URLocationCoordinate3D(latitude: latitude, longitude: longitude, altitude: altitude)
        
        let directionAndDistance = userLocation.distanceAndDistance(from: metaData.locationCoordinate)
        
        receiverLastDirectionDegrees = directionAndDistance.direction
        receiverLastDistanceMeters = directionAndDistance.distance
    }
}
