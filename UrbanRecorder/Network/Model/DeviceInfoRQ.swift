//
//  DeviceInfoRQ.swift
//  UrbanRecorder
//
//  Created by ting hui wu on 2021/10/28.
//

import Foundation

struct DeviceInfoRQ: Codable {
    
    let deviceID: String
    
    let socketID: String
    
    let userID: String
}
