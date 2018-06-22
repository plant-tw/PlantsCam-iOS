//
//  ExifUserComment.swift
//  ARSampleApp
//
//  Created by denkeni on 05/10/2017.
//  Copyright © 2017 Droids On Roids. All rights reserved.
//

struct ExifUserComment : Codable {

    let lengthInPixel : Float
    let lengthInCentiMeter : Float

    let roll : Double
    let pitch : Double
    let yaw : Double

    let latitude : Double
    let longitude : Double
}
