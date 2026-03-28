//
//  Helpers.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/16/23.
//

import Foundation

public func getHostAndPort(
    from urlString: String, defaultPort: Int = 70, defaultHost: String = "gopher.navan.dev"
) -> (host: String, port: Int, selector: String) {
    if let urlComponents = URLComponents(string: urlString),
        let host = urlComponents.host
    {
        let port = urlComponents.port ?? defaultPort
        let selector = urlComponents.path
        return (host, port, selector)
    } else {
        let components = urlString.split(separator: ":")
        let host = components.first.map(String.init) ?? defaultHost

        var port = (components.count > 1 ? Int(components[1]) : nil) ?? defaultPort
        var selector = "/"

        if components.count > 1 {
            let portCompString = components[1]
            let portCompComponents = portCompString.split(separator: "/", maxSplits: 1)
            if portCompComponents.count > 1 {
                port = Int(portCompComponents[0]) ?? defaultPort
                selector = "/" + portCompComponents[1]
            } else if portCompComponents.count == 1 {
                port = Int(portCompComponents[0]) ?? defaultPort
            }
        }

        return (host, port, selector)
    }
}
