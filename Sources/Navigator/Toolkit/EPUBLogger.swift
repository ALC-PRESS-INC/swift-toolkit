//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import os.log

public struct EPUBLogger {

//    private static let log = OSLog.init(
//        subsystem: "ph.com.alc-tech.readium",
//        category: "Readium-swift-toolkit"
//    )
//
//    public static func log(with object: Any) {
//        os_log(
//            "Value: %{public}@",
//            log: log,
//            type: .debug,
//            String(describing: object)
//        )
//    }

    @available(iOS 14.0, *)
    private static let logger = Logger(
        subsystem: "ph.com.alc-tech.readium",
        category: "Readium-swift-toolkit"
    )

    @available(iOS 14.0, *)
    public static func log(with object: Any) {
        //logger.debug("THIS IS FROM READIUM: \(String(describing: object), privacy: .public)")
        NSLog("THIS IS FROM READIUM: %@", String(describing: object))
    }

}
