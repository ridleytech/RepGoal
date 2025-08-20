//
//  Item.swift
//  RepGoal
//
//  Created by Randall Ridley on 8/13/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
