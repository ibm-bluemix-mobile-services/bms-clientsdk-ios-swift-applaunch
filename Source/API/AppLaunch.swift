//
//  AppLaunch.swift
//  AppLaunch
//
//  Created by Chethan Kumar on 9/23/17.
//  Copyright © 2017 IBM. All rights reserved.
//

import Foundation
import BMSCore
import SwiftyJSON

// ─────────────────────────────────────────────────────────────────────────

public class AppLaunch:NSObject{
    
    public private(set) var clientSecret: String?
    
    public private(set) var applicationId: String?
    
    public private(set) var region: String?
    
    private var deviceId = String()
    
    public static let sharedInstance = AppLaunch()
    
    private var bmsClient = BMSClient.sharedInstance
    
    private var isInitialized = false
    
    private var isUserRegistered = false
    
    private var userId:String = String()
    
    private var features:JSON = JSON.null
    
    private var URLBuilder:AppLaunchURLBuilder? = nil
    
    /**
     intializes app
     
     - parameters:
     - applicationId: app GUID value
     - clientSecret: clientSecret appLaunch client secret value
     - region: bluemixRegionSuffix specifies the location where the app is hosted
     */
    public func initializeWithAppGUID (applicationId: String, clientSecret: String, region: String) {
        
        if AppLaunchUtils.validateString(object: clientSecret) &&  AppLaunchUtils.validateString(object: applicationId) && AppLaunchUtils.validateString(object: region){
            
            self.clientSecret = clientSecret
            self.applicationId = applicationId
            self.region = region
            AppLaunchFileManager.loadFeatureFromFiles()
            self.features = AppLaunchFileManager.loadFeatures()
            
            if(UserDefaults.standard.value(forKey: USER_ID) != nil){
                self.userId = UserDefaults.standard.value(forKey: USER_ID) as! String
            }else{
                self.userId = ""
            }
            
            self.URLBuilder = AppLaunchURLBuilder(region, applicationId)
            isInitialized = true;
            
            let authManager  = BMSClient.sharedInstance.authorizationManager
            self.deviceId = authManager.deviceIdentity.ID!
            AppLaunchUtils.saveValueToNSUserDefaults(value: self.deviceId, key: DEVICE_ID)
        }
        else{
            print(MSG__CLIENT_OR_APPID_NOT_VALID)
        }
    }
    
    /**
     Registers app with server
     
     - returns
     Completion Handler with response, statuscode and error object
     
     - parameters:
     - userID: user ID value
     */
    public func registerWith(userId:String,completionHandler:@escaping(_ response:String, _ statusCode:Int, _ error:String) -> Void){
        if(isInitialized) {
            
            if(!AppLaunchUtils.userNeedsToBeRegistered(userId: userId, applicationId: self.applicationId!, deviceId: self.deviceId, region: self.region!)){
                self.userId = userId
                completionHandler(MSG__USER_ALREADY_REGISTERED,201,"")
            } else {
                var deviceData:JSON = JSON()
                deviceData[DEVICE_ID].string = self.deviceId
                deviceData[MODEL].string = UIDevice.current.modelName
                deviceData[BRAND].string = APPLE
                deviceData[OS_VERSION].string = UIDevice.current.systemVersion
                deviceData[PLATFORM].string = IOS
                deviceData[APP_ID].string = Bundle.main.bundleIdentifier!
                deviceData[APP_VERSION].string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                deviceData[APP_NAME].string = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                deviceData[USER_ID].string = userId
                
                let request = AppLaunchInvoker(url: URLBuilder!.getAppRegistrationURL(), method: HttpMethod.POST, timeout: 60)
                request.addHeader(APPLICATION_JSON, CONTENT_TYPE)
                request.addHeader(self.clientSecret!, CLIENT_SECRET)
                request.setJSONRequestBody(deviceData)
                request.setCompletionHandler({(response,error) in
                    if(response != nil){
                        let responseText = response?.responseText ?? ""
                        let status = response?.statusCode ?? 0
                        if(status == 200 || status == 201){
                            self.isUserRegistered = true
                            self.userId = userId
                            AppLaunchUtils.saveUserContext(userId: userId, applicationId: self.applicationId!, deviceId: self.deviceId, region: self.region!)
                            AppLaunchUtils.saveValueToNSUserDefaults(value: TRUE, key: IS_USER_REGISTERED)
                            completionHandler(responseText,status,"")
                        }else{
                            completionHandler("", status, responseText)
                            self.isUserRegistered = false
                        }
                    }else if let responseError = error{
                        completionHandler("", 500, responseError.localizedDescription)
                    }
                })
                request.execute()
            }
        }
    }
    
    /**
     Updates User Information
     
     - returns
     Completion handler with response, statuscode and error object
     
     - parameters:
     - userID: user ID value
     - attribute: user attribute value
     */
    public func updateUserWith(userId:String,attribute:String,value:Any, completionHandler:@escaping(_ response:String, _ statusCode:Int, _ error:String) -> Void){
        
        var deviceData:JSON = JSON()
        deviceData[DEVICE_ID].string = self.deviceId
        deviceData[USER_ID].string = self.userId
        switch type(of: value) {
        case is String.Type:
            deviceData[attribute].string = value as? String
            
        case is Numeric.Type:
            deviceData[attribute].number = value as? NSNumber
            
        case is Bool.Type:
            deviceData[attribute].boolValue = value as! Bool
            
        default:
            break
        }
        
        let request = AppLaunchInvoker(url: (URLBuilder?.getUserURL(self.userId))!, method: HttpMethod.PUT, timeout: 60)
        request.addHeader(APPLICATION_JSON, CONTENT_TYPE)
        request.addHeader(self.clientSecret!, CLIENT_SECRET)
        request.setJSONRequestBody(deviceData)
        request.setCompletionHandler({(response,error) in
            if(response != nil){
                let responseText = response?.responseText ?? ""
                let status = response?.statusCode ?? 0
                if(status == 200 || status == 201){
                    self.isUserRegistered = true
                    AppLaunchUtils.saveUserContext(userId: userId, applicationId: self.applicationId!, deviceId: self.deviceId, region: self.region!)
                    AppLaunchUtils.saveValueToNSUserDefaults(value: TRUE, key: IS_USER_REGISTERED)
                    self.userId = userId
                    completionHandler(responseText,status,"")
                }else{
                    completionHandler("", status, responseText)
                    self.isUserRegistered = false
                }
            }else if let responseError = error{
                completionHandler("", 500, responseError.localizedDescription)
            }
        })
        request.execute()
        
    }
    
    /**
     Actions API
     
     - returns
     Completion handler with features JSON object, statuscode and error object
     */
    public func actions(completionHandler:@escaping(_ features:JSON?, _ statusCode:Int?, _ error:String) -> Void){
        
        if(isInitialized && !AppLaunchUtils.userNeedsToBeRegistered(userId: self.userId, applicationId: self.applicationId!, deviceId: self.deviceId, region: self.region!)){
            
            let request = AppLaunchInvoker(url: (URLBuilder?.getActionURL(self.userId))!, method: HttpMethod.GET, timeout: 60)
            request.addHeader(CONTENT_TYPE, APPLICATION_JSON)
            request.addHeader(self.clientSecret!, CLIENT_SECRET)
            request.addQueryParameter(self.deviceId, DEVICE_ID)
            request.setCompletionHandler({ (response, error) in
                if response != nil {
                    let status = response?.statusCode ?? 0
                    let responseText = response?.responseText ?? ""
                    
                    if(status == 200 || status == 201){
                        if let data = responseText.data(using: String.Encoding.utf8) {
                            do {
                                let respJson = try JSON(data: data)
                                print("response data from server \(responseText)")
                                AppLaunchFileManager.saveFeatures(data: respJson["features"])
                                self.features = AppLaunchFileManager.loadFeatures()
                                completionHandler(respJson["features"],200,"")
                            } catch {
                                completionHandler(nil,404,error.localizedDescription)
                            }
                        }
                    }else{
                        print("[404] Actions Not found")
                        completionHandler(nil,status,responseText)
                    }
                    
                }else {
                    completionHandler([], 500 , MSG__ERR_GET_ACTIONS)
                }
            })
            request.execute()
            
        }else{
            completionHandler([], 500 , MSG__ERR_NOT_REG_NOT_INIT)
            
        }
    }
    
    /**
     Checks if the feature is enabled for the app
     
     - returns
     Bool value
     */
    public func hasFeatureWith(code:String) -> Bool{
        var hasFeature = false
        for(_,feature) in self.features{
            if let featureCode = feature["code"].string{
                if featureCode == code{
                    hasFeature = true
                }
            }
        }
        return hasFeature
    }
    
    
    //has been deprecated
    public func getValueFor(featureWithCode:String,variableWithCode:String) -> String{
        for(_,feature) in self.features{
            if let featureCode = feature["code"].string{
                if featureCode == featureWithCode{
                    for(_,variable) in feature["variables"]{
                        if let varibleCode = variable["code"].string{
                            if varibleCode == variableWithCode{
                                return variable["value"].stringValue
                            }
                        }
                    }
                }
            }
        }
        return ""
    }
    
    /**
     Returns the value for particular property in a feature
     
     - returns
     String value of the property
     
     - parameters:
     - featureWithCode: feature code
     - propertiesWithCode: property code
     */
    public func getValueFor(featureWithCode:String,propertiesWithCode:String) -> String{
        for(_,feature) in self.features{
            if let featureCode = feature["code"].string{
                if featureCode == featureWithCode{
                    for(_,variable) in feature["variables"]{
                        if let varibleCode = variable["code"].string{
                            if varibleCode == propertiesWithCode{
                                return variable["value"].stringValue
                            }
                        }
                    }
                }
            }
        }
        return ""
    }
    
    /**
     Sends metrics information to App Launch Server
     
     - parameters:
     - code: metric code
     */
    public func sendMetricsWith(code:String) -> Void{
        if(isInitialized && !AppLaunchUtils.userNeedsToBeRegistered(userId: self.userId, applicationId: self.applicationId!, deviceId: self.deviceId, region: self.region!)){
            
            var metricsData:JSON = JSON()
            metricsData[DEVICE_ID].string = self.deviceId
            metricsData[USER_ID].string = self.userId
            metricsData[METRIC_CODES].arrayObject = [code]
            
            print("metrics payload \(metricsData.description)")
            
            let request = AppLaunchInvoker(url: (URLBuilder?.getMetricsURL(self.userId))!, method: HttpMethod.POST, timeout: 60)
            request.addHeader(CONTENT_TYPE, APPLICATION_JSON)
            request.addHeader(self.clientSecret!, CLIENT_SECRET)
            request.addQueryParameter(self.deviceId, DEVICE_ID)
            request.setCompletionHandler({(response,error) in
                
                let status = response?.statusCode ?? 0
                if(status == 200){
                    print("sent metrics for code : \(code)")
                }else if let responseError = error{
                    print("Error in sending metrics for code : \(code) with error :\(responseError.localizedDescription)")
                }
                
            })
            request.execute()
        }else{
            print(MSG__ERR_METRICS_NOT_INIT)
        }
        
    }
    
    
}