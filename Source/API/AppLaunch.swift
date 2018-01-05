//
//  AppLaunch.swift
//  AppLaunch
//
//  Created by Chethan Kumar & Vittal Pai on 9/23/17.
//  Copyright © 2017 IBM. All rights reserved.
//

import Foundation
import BMSCore
import SwiftyJSON

// MARK: - Swift 3 & Swift 4

/**
 A singleton that serves as an entry point to IBM Cloud AppLaunch service communication.
 */
public class AppLaunch: NSObject {
    
    // MARK: Properties
    
    /// This singleton should be used for all `AppLaunch` activity.
    public static let sharedInstance = AppLaunch()
    
    private var isInitialized = false
    
    private var isUserRegistered = false
    
    private var URLBuilder: AppLaunchURLBuilder? = nil
    
    private var user: AppLaunchUser!
    
    private var config: AppLaunchConfig!
    
    // MARK: Methods
    
    /**
     The required initializer for the `AppLaunch` class.
     
     This method will intialize the AppLaunch with appID, clientSecret and region based registration.
     
     - parameter region: IBM Cloud region suffix specifies the location where the AppLaunch service is hosted
     - parameter applicationId: app GUID value
     - parameter clientSecret: appLaunch client secret value
     - parameter config: appLaunch client configuration object
     - parameter user: appLaunch client user object
     - parameter completionHandler: A completion-handler callback function. In the case of a successful intialization, the actions JSON is returned in the AppLaunchResponse. In the case of a unsuccessful completion, the error code and the information is returned in the AppLaunchFailResponse
     */
    public func initialize(region: ICRegion, appId: String, clientSecret: String, config: AppLaunchConfig, user: AppLaunchUser, completionHandler: @escaping AppLaunchCompletionHandler) {
        
        if AppLaunchUtils.validateString(object: clientSecret) &&  AppLaunchUtils.validateString(object: appId) && AppLaunchUtils.validateString(object: user.getUserId() ){
            config.setICRegion(region.rawValue)
            config.setAppID(appId)
            config.setClientSecret(clientSecret)
            self.config = config
            self.user = user
            self.URLBuilder = AppLaunchURLBuilder(config.getICRegion(), config.getAppID(), config.getDeviceID())
            AppLaunchCacheManager.sharedInstance.loadDefaultFeatures(completionHandler)
            IntializeSession()
            //Register User
            registerDevice(completionHandler)
            isInitialized = true
        }
        else{
            print(MSG__CLIENT_OR_APPID_NOT_VALID)
        }
    }
    
    
    
    
    /**
     This Methode used to unregister the device from the IBM Cloud AppLaunch service and It clears the stored cache.
     
     - parameter completionHandler: A completion-handler callback function. In the case of a successful completion, the success information is returned in the AppLaunchResponse. In the case of a unsuccessful completion, the error information is returned in the AppLaunchFailResponse
     */
    public func destroy(completionHandler: @escaping AppLaunchCompletionHandler) {
        if(isInitialized) {
            let request = AppLaunchInvoker(url: URLBuilder!.getUserURL(), method: HttpMethod.DELETE, timeout: 60)
            request.addHeader(config.getClientSecret(), CLIENT_SECRET)
            request.setCompletionHandler({(response,error) in
                if(response != nil){
                    let responseText = response?.responseText ?? ""
                    let status = response?.statusCode ?? 0
                    if(status == 204){
                        // Clear registration data and actions
                        self.isUserRegistered = false
                        AppLaunchCacheManager.sharedInstance.clearUserDefaults()
                    }else{
                        completionHandler(nil, AppLaunchFailResponse(.UNREGISTRATION_FAILURE, responseText))
                    }
                }else {
                    completionHandler(nil, AppLaunchFailResponse(.UNREGISTRATION_FAILURE, (error?.localizedDescription)!))
                }
            })
            request.execute()
        } else {
            completionHandler(nil, AppLaunchFailResponse(.UNREGISTRATION_FAILURE, "AppLaunch SDK is not Initialized"))
        }
    }
    
    /**
     
     This Methode used to send metrics information to the IBM Cloud AppLaunch service.
     
     - Parameter code: This is the array of metric codes.
     */
    public func sendMetricsWith(codes: [String]) -> Void {
        if(!AppLaunchUtils.userNeedsToBeRegistered() && isInitialized){
            var metricsData:JSON = JSON()
            metricsData[METRIC_CODES].arrayObject = codes
            let request = AppLaunchInvoker(url: (URLBuilder?.getMetricsURL())!, method: HttpMethod.POST, timeout: 60)
            request.addHeader(APPLICATION_JSON, CONTENT_TYPE)
            request.addHeader(config.getClientSecret(), CLIENT_SECRET)
            request.setJSONRequestBody(metricsData)
            request.setCompletionHandler({(response,error) in
                
                let status = response?.statusCode ?? 0
                if(status == 200){
                    print("sent metrics successfully for the code(s) : \(codes.joined(separator: ", "))")
                }else if let responseError = error{
                    print("Error in sending metrics for the code(s) : \(codes.joined(separator: ", ")) with error :\(responseError.localizedDescription)")
                }
                
            })
            request.execute()
        }else{
            print(MSG__ERR_METRICS_NOT_INIT)
        }
        
    }
    
    public func sendSessionLogs() {
        Analytics.send()
    }
    
    /**
     Checks if the feature is enabled for the app
     
     - returns
     Bool value
     */
    public func hasFeatureWith(code:String) -> Bool{
        if(AppLaunchCacheManager.sharedInstance.readJSON(code) != JSON.null) {
            return true
        }
        return false
    }
    
    /**
     Returns the value for particular property in a feature
     
     - returns
     String value of the property or Empty string if property/feature doesn't exist
     
     - parameters:
     - featureWithCode: feature code
     - propertyWithCode: property code
     */
    public func getValueFor(featureWithCode:String , propertyWithCode:String) -> String{
        let feature = AppLaunchCacheManager.sharedInstance.readJSON(featureWithCode)
        if (feature != JSON.null) {
            for(_,property) in feature[PROPERTIES]{
                if let propertyCode = property[CODE].string{
                    if propertyCode == propertyWithCode{
                        return property[VALUE].stringValue
                    }
                }
            }
        }
        return ""
    }
    
    
    
    // Private Methods
    
    /**
     
     This Methode used to register the client device to the IBM Cloud AppLaunch service.
     
     - Parameter userID: This is the userId value.
     - Parameter attributes: This is the attributes value.
     
     - returns: AppLaunchCompletionHandler: A completion-handler callback function. In the case of a successful completion, the success information is returned in the AppLaunchResponse. In the case of a unsuccessful completion, the error information is returned in the AppLaunchFailResponse
     */
    private func registerDevice(_ completionHandler: @escaping AppLaunchCompletionHandler){
        if(!AppLaunchUtils.userNeedsToBeRegistered() && !AppLaunchUtils.isUpdateRegistrationRequired(user, config) ) {
            // User Already Registered, Proceed with getActions Call
            Analytics.userIdentity = user.getUserId()
            getActions(completionHandler)
        } else {
            var method:HttpMethod = HttpMethod.POST
            if AppLaunchUtils.isUpdateRegistrationRequired(user, config) {
                // Update Registration Call
                method = HttpMethod.PUT
            }
            let registrationData:JSON = AppLaunchUtils.getRegistrationData(user, config)
            let request = AppLaunchInvoker(url: URLBuilder!.getAppRegistrationURL(), method: method, timeout: 60)
            request.addHeader(APPLICATION_JSON, CONTENT_TYPE)
            request.addHeader(config.getClientSecret(), CLIENT_SECRET)
            request.setJSONRequestBody(registrationData)
            request.setCompletionHandler({(response,error) in
                let status = response?.statusCode ?? 0
                if(response != nil){
                    if(status == 200 || status == 201 || status == 202 || status == 405){
                        // Registration Success. Save User Context and proceed with getActions Call
                        Analytics.userIdentity = self.user.getUserId()
                        AppLaunchUtils.saveUserContext(self.user, self.config)
                        self.getActions(completionHandler)
                    }else{
                        if (status == 400) {
                            self.isUserRegistered = false
                            AppLaunchCacheManager.sharedInstance.clearUserDefaults()
                        }
                        completionHandler(nil, AppLaunchFailResponse(.REGISTRATION_FAILURE ,  (response?.responseText)!))
                    }
                }else {
                    completionHandler(nil, AppLaunchFailResponse(.REGISTRATION_FAILURE , (error?.localizedDescription)!))
                }
            })
            request.execute()
        }
    }
    
    private func getActions(_ completionHandler: @escaping AppLaunchCompletionHandler) {
        let policy = config.getPolicy()
        switch(policy) {
        case .REFRESH_ON_EVERY_START : fetchActions(completionHandler)
            break
        case .REFRESH_ON_EXPIRY : let expirationTimeString = AppLaunchCacheManager.sharedInstance.readString(CACHE_EXPIRATION).isEmpty ? "0" : AppLaunchCacheManager.sharedInstance.readString(CACHE_EXPIRATION)
        let expirationTime = Int(expirationTimeString)!
        let currentTime = AppLaunchUtils.getCurrentDateAndTime()
        if expirationTime < currentTime {
            fetchActions(completionHandler)
        } else {
            if (AppLaunchCacheManager.sharedInstance.readJSON(ACTION) != JSON.null) {
                completionHandler(AppLaunchResponse(AppLaunchCacheManager.sharedInstance.readJSON(ACTION)), nil)
            } else {
                fetchActions(completionHandler)
            }
        }
            break
        case .BACKGROUND_REFRESH :
            // TODO :  Background Refresh Mechanism
            fetchActions(completionHandler)
            break
        }
    }
    
    
    /**
     
     This Methode used to get all the available actions from the IBM Cloud AppLaunch service.
     
     - returns: AppLaunchCompletionHandler: A completion-handler callback function. In the case of a successful completion, the actions information is returned in the AppLaunchResponse. In the case of a unsuccessful completion, the error information is returned in the AppLaunchFailResponse
     */
    private func fetchActions(_ completionHandler: @escaping AppLaunchCompletionHandler){
        let request = AppLaunchInvoker(url: (URLBuilder?.getActionURL())!, method: HttpMethod.GET, timeout: 60)
        request.addHeader(config.getClientSecret() , CLIENT_SECRET)
        request.setCompletionHandler({ (response, error) in
            if response != nil {
                let status = response?.statusCode ?? 0
                let responseText = response?.responseText ?? ""
                
                if(status == 200 || status == 201){
                    if let data = responseText.data(using: String.Encoding.utf8) {
                        do {
                            let respJson = try JSON(data: data)
                            print("response data from server \(responseText)")
                            let ExpirationTime = String(Int(AppLaunchUtils.getCurrentDateAndTime()) + (self.config.getCacheExpiration() * 60))
                            AppLaunchCacheManager.sharedInstance.addString(ExpirationTime, CACHE_EXPIRATION)
                            AppLaunchCacheManager.sharedInstance.addString(respJson.rawString()!, ACTION)
                            AppLaunchCacheManager.sharedInstance.addActions(respJson[FEATURES])
                            AppLaunchCacheManager.sharedInstance.addInAppActionToCache(respJson[INAPP])
                            self.processInAppActions()
                            completionHandler(AppLaunchResponse(respJson), nil)
                        } catch {
                            completionHandler(nil, AppLaunchFailResponse(.FETCH_ACTIONS_FAILURE , error.localizedDescription))
                        }
                    }
                }else{
                    print("[404] Actions Not found")
                    completionHandler(nil, AppLaunchFailResponse(.FETCH_ACTIONS_FAILURE , responseText))
                }
                
            }else {
                completionHandler(nil, AppLaunchFailResponse(.FETCH_ACTIONS_FAILURE, (error?.localizedDescription)!))
            }
        })
        request.execute()
    }
    
    private func displayInAppMessage(_ action: JSON) -> Void {
        let layout : String = action[LAYOUT].stringValue
        switch(layout){
        case MessageType.Banner.rawValue:
            AppLaunchInAppMessaging(action).ShowBanner()
            break
        default :
            break
        }
    }
    
    private func processInAppActions() -> Void {
        let InAppActions = AppLaunchCacheManager.sharedInstance.readJSON(INAPP)
        for (_, action) in InAppActions {
            for (_, trigger) in action[TRIGGERS] {
                let triggerAction : String = trigger[ACTION].stringValue
                switch(triggerAction){
                case TriggerType.EveryLaunch.rawValue :
                    displayInAppMessage(action)
                    break
                case TriggerType.FirstLaunch.rawValue :
                    let previousDateString = AppLaunchCacheManager.sharedInstance.readString(action[NAME].stringValue + triggerAction).isEmpty ? "0" : AppLaunchCacheManager.sharedInstance.readString(action[NAME].stringValue + triggerAction)
                    let previousDate = Int(previousDateString)!
                    let currentDate = AppLaunchUtils.getCurrentDate()
                    // Check if date changed or not
                    if(currentDate > previousDate) {
                        displayInAppMessage(action)
                        AppLaunchCacheManager.sharedInstance.addString(String(AppLaunchUtils.getCurrentDate()), action[NAME].stringValue + triggerAction)
                    }
                    break
                case TriggerType.EveryAlternateLaunch.rawValue :
                    if(AppLaunchCacheManager.sharedInstance.readString(action[NAME].stringValue + triggerAction).isEmpty) {
                        displayInAppMessage(action)
                        AppLaunchCacheManager.sharedInstance.addString(triggerAction, action[NAME].stringValue + triggerAction)
                    } else {
                        AppLaunchCacheManager.sharedInstance.clearString(action[NAME].stringValue + triggerAction)
                    }
                    break
                case TriggerType.OnceAndOnlyOnce.rawValue :
                    if(AppLaunchCacheManager.sharedInstance.readString(action[NAME].stringValue + triggerAction).isEmpty) {
                        displayInAppMessage(action)
                        AppLaunchCacheManager.sharedInstance.addString(triggerAction, action[NAME].stringValue + triggerAction)
                    }
                    break
                default :
                    break
                }
            }
        }
    }
    
    private func IntializeSession() {
        Analytics.initialize(config: config, url: (URLBuilder?.getSessionURL())!, hasUserContext: true, collectLocation: false, deviceEvents: .lifecycle, .network)
        Analytics.isEnabled = true
        Logger.isLogStorageEnabled = true
        Logger.isInternalDebugLoggingEnabled = true
        Logger.logLevelFilter = LogLevel.error
    }
}

