//
//  FCMChannelQuickReply.swift
//  Alamofire
//
//  Created by Daniel Amaral on 28/06/18.
//

import UIKit
import ObjectMapper

open class FCMChannelQuickReply: NSObject, Mappable {
        
    open var title: String = ""
    
    required public init?(map: Map) {}

    init(_ title: String) {
        self.title = title
    }

    open func mapping(map: Map) {
        self.title <- map["title"]
    }
}
