//
//  Item.swift
//  StoriesConcept
//
//  Created by Juan Colilla on 15/3/26.
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
