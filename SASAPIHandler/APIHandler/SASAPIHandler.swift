//
//  SASAPIHandler.swift
//  SASAPIHandler
//
//  Created by Sasikumar on 04/02/18.
//  Copyright © 2018 Sasikumar. All rights reserved.
//
 
import UIKit
import SystemConfiguration

enum SASAPIMethod :String {
    
    case POST
    case GET
    case PUT
    case DELETE
    
    func getMethod() -> String { return self.rawValue}
}

enum SASRequestType : Int {
    case FormData
    case URLEncoded
    case JsonData
}

class SASAPIHandler: NSObject
{
    static let shared = SASAPIHandler()
    
    public var baseURL = "" // Base url
    
    public var timeOutInterval : TimeInterval = 100
    
    
    func callAPI(endPoint:String, method:SASAPIMethod, requestType:SASRequestType = .JsonData,header : [String:String]? = nil,parameter:[String:Any]? = nil, isCacheEnabled:Bool = false,completion: @escaping (_ response: Any?, _ error: Error?, _ statusCode : Int ) -> Void) {
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        guard let url = URL(string: self.baseURL + endPoint) else {
            print("Oops!: Unsupported URL, Please check your base URL. if it is configured in appDeletegate or not")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: self.timeOutInterval)
            
            request.httpMethod = method.getMethod()
            
            if method != .GET
            {
                if let parameter = parameter
                {
                    switch requestType {
                        
                    case .FormData:
                       
                        let boundary = "Boundary-\(NSUUID().uuidString)"
                        var body = ""
                        
                        for (paramName, paramValue) in parameter
                        {
                            body += "--\(boundary)\r\n"
                            body += "Content-Disposition: form-data; name=\"\(paramName)\"\r\n\r\n"
                            body += "\(paramValue)\r\n"
                        }
                        
                        body += "--\(boundary)--\r\n"
                        let data = body.data(using: String.Encoding.utf8, allowLossyConversion: false)
                        request.httpBody = data
                        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                        
                    case .URLEncoded:
                        
                        var body = ""
                        var isFirst = true
                        
                        for (paramName, paramValue) in parameter
                        {
                            if isFirst
                            {
                                isFirst = false
                                body += "\(paramName)=\(paramValue)"
                            }
                            else
                            {
                                body += "&\(paramName)=\(paramValue)"
                            }
                        }
                        
                        request.httpBody = body.data(using: String.Encoding.utf8)
                        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
                        
                    case .JsonData:
                        
                        let jsonData = try? JSONSerialization.data(withJSONObject: parameter, options: .prettyPrinted)
                        request.httpBody = jsonData
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("application/json", forHTTPHeaderField: "Accept")
                    }
                }
            }
            
            if let header = header
            {
                for (key,value) in header
                {
                     request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            if let cacheResponse = URLCache.shared.cachedResponse(for: request), isCacheEnabled == true
            {
                DispatchQueue.main.async {
                    UIApplication.shared.isNetworkActivityIndicatorVisible = false
                    let jsonDictionary = try? JSONSerialization.jsonObject(with: cacheResponse.data, options: [])
                    completion(jsonDictionary, nil,200)
                }
            }
            else
            {
                let config = URLSessionConfiguration.default
                config.urlCache = URLCache.shared
                config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, diskPath: "URLCACHE")
                
                let session = URLSession(configuration: config)
                
                let task = session.dataTask(with: request) { data, response, error in
                    DispatchQueue.main.async {
                        
                        UIApplication.shared.isNetworkActivityIndicatorVisible = false
                        
                        var statusCode = 0
                        
                        guard let data = data, error == nil else {
                            completion(nil, error, statusCode)
                            return
                        }
                        
                        if let httpStatus = response as? HTTPURLResponse
                        {
                            statusCode = httpStatus.statusCode
                        }
                        
                        let jsonDictionary = try? JSONSerialization.jsonObject(with: data, options: [])
                        
                        completion(jsonDictionary, nil,statusCode)
                        
                        if let response = response
                        {
                            let cacheResponse = CachedURLResponse(response: response, data: data)
                            URLCache.shared.storeCachedResponse(cacheResponse, for: request)
                        }
                    }
                }
                
                task.resume()
            }
        }
    }
}



public class SASReachability {
    
    class func isConnectedToNetwork() -> Bool {
        
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return isReachable && !needsConnection
    }
}
