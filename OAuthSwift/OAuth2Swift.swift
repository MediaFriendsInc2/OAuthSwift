//
//  OAuth2Swift.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 6/22/14.
//  Copyright (c) 2014 Dongri Jin. All rights reserved.
//

import Foundation

open class OAuth2Swift: OAuthSwift {

    // If your oauth provider need to use basic authentification
    // set value to true (default: false)
    open var accessTokenBasicAuthentification = false

    // Set to true to deactivate state check. Be careful of CSRF
    open var allowMissingStateCheck: Bool = false

    var consumer_key: String
    var consumer_secret: String
    var authorize_url: String
    var access_token_url: String?
    var response_type: String
    var content_type: String?
    
    // MARK: init
    public convenience init(consumerKey: String, consumerSecret: String, authorizeUrl: String, accessTokenUrl: String, responseType: String){
        self.init(consumerKey: consumerKey, consumerSecret: consumerSecret, authorizeUrl: authorizeUrl, responseType: responseType)
        self.access_token_url = accessTokenUrl
    }

    public convenience init(consumerKey: String, consumerSecret: String, authorizeUrl: String, accessTokenUrl: String, responseType: String, contentType: String){
        self.init(consumerKey: consumerKey, consumerSecret: consumerSecret, authorizeUrl: authorizeUrl, responseType: responseType)
        self.access_token_url = accessTokenUrl
        self.content_type = contentType
    }

    public init(consumerKey: String, consumerSecret: String, authorizeUrl: String, responseType: String){
        self.consumer_key = consumerKey
        self.consumer_secret = consumerSecret
        self.authorize_url = authorizeUrl
        self.response_type = responseType
        super.init(consumerKey: consumerKey, consumerSecret: consumerSecret)
        self.client.credential.version = .oauth2
    }
    
    public convenience init?(parameters: ConfigParameters){
        guard let consumerKey = parameters["consumerKey"], let consumerSecret = parameters["consumerSecret"],
            let responseType = parameters["responseType"], let authorizeUrl = parameters["authorizeUrl"] else {
                return nil
        }
        if let accessTokenUrl = parameters["accessTokenUrl"] {
            self.init(consumerKey:consumerKey, consumerSecret: consumerSecret,
                authorizeUrl: authorizeUrl, accessTokenUrl: accessTokenUrl, responseType: responseType)
        } else {
            self.init(consumerKey:consumerKey, consumerSecret: consumerSecret,
                authorizeUrl: authorizeUrl, responseType: responseType)
        }
    }

    open var parameters: ConfigParameters {
        return [
            "consumerKey": consumer_key,
            "consumerSecret": consumer_secret,
            "authorizeUrl": authorize_url,
            "accessTokenUrl": access_token_url ?? "",
            "responseType": response_type
        ]
    }

    // MARK: functions
    open func authorize(withCallbackURL callbackURL: URL, scope: String, state: String, parameters: Parameters = [:], headers: OAuthSwift.Headers? = nil, success: @escaping TokenSuccessHandler, failure: FailureHandler?)  -> OAuthSwiftRequestHandle? {
        
        self.observeCallback { [weak self] url in
            guard let this = self else { OAuthSwift.retainError(failure); return }
            var responseParameters = [String: String]()
            if let query = url.query {
                responseParameters += query.parametersFromQueryString()
            }
            if let fragment = url.fragment , !fragment.isEmpty {
                responseParameters += fragment.parametersFromQueryString()
            }
            if let accessToken = responseParameters["access_token"] {
                this.client.credential.oauth_token = accessToken.safeStringByRemovingPercentEncoding
                if let expiresIn:String = responseParameters["expires_in"], let offset = Double(expiresIn)  {
                    this.client.credential.oauth_token_expires_at = Date(timeInterval: offset, since: Date())
                }
                success(this.client.credential, nil, responseParameters)
            }
            else if let code = responseParameters["code"] {
                if !this.allowMissingStateCheck {
                    guard let responseState = responseParameters["state"] else {
                        failure?(OAuthSwiftError.missingState)
                        return
                    }
                    if responseState != state {
                        failure?(OAuthSwiftError.stateNotEqual(state: state, responseState: responseState))
                        return
                    }
                }
                let _ = this.postOAuthAccessTokenWithRequestToken(
                    byCode: code.safeStringByRemovingPercentEncoding,
                    callbackURL:callbackURL, headers: headers , success: success, failure: failure)
                // TODO CANCEL REQUEST keep the returned handle into a list for cancel
            }
            else if let error = responseParameters["error"] {
                let description = responseParameters["error_description"] ?? ""
                let message = NSLocalizedString(error, comment: description)
                failure?(OAuthSwiftError.serverError(message: message))
            }
            else {
                let message = "No access_token, no code and no error provided by server"
                failure?(OAuthSwiftError.serverError(message: message))
            }
        }

        
        var queryString = "client_id=\(self.consumer_key)"
        queryString += "&redirect_uri=\(callbackURL.absoluteString)"
        queryString += "&response_type=\(self.response_type)"
        if !scope.isEmpty {
            queryString += "&scope=\(scope)"
        }
        if !state.isEmpty {
            queryString += "&state=\(state)"
        }
        for param in parameters {
            queryString += "&\(param.0)=\(param.1)"
        }
        
        var urlString = self.authorize_url
        urlString += (self.authorize_url.has("?") ? "&" : "?")
        
        if let encodedQuery = queryString.urlQueryEncoded, let queryURL = URL(string: urlString + encodedQuery) {
            self.authorizeURLHandler.handle(queryURL)
        }
        else {
            failure?(OAuthSwiftError.encodingError(urlString: urlString))
        }
        return self
    }
    
    open func authorize(withCallbackURL urlString: String, scope: String, state: String, parameters: Parameters = [:], headers: OAuthSwift.Headers? = nil, success: @escaping TokenSuccessHandler, failure: FailureHandler?) -> OAuthSwiftRequestHandle? {
        guard let url = URL(string: urlString) else {
            failure?(OAuthSwiftError.encodingError(urlString: urlString))
            return nil
        }
        return authorize(withCallbackURL: url, scope: scope, state: state, parameters: parameters, headers: headers, success: success, failure: failure)
    }

    func postOAuthAccessTokenWithRequestToken(byCode code: String, callbackURL: URL, headers: OAuthSwift.Headers? = nil, success: @escaping TokenSuccessHandler, failure: FailureHandler?) -> OAuthSwiftRequestHandle? {
        var parameters = OAuthSwift.Parameters()
        parameters["client_id"] = self.consumer_key
        parameters["client_secret"] = self.consumer_secret
        parameters["code"] = code
        parameters["grant_type"] = "authorization_code"
        parameters["redirect_uri"] = callbackURL.absoluteString.safeStringByRemovingPercentEncoding

        return requestOAuthAccessToken(withParameters: parameters, headers: headers, success: success, failure: failure)
    }
    
    open func renewAccessToken(withRefreshToken refreshToken: String, headers: OAuthSwift.Headers? = nil, success: @escaping TokenSuccessHandler, failure: FailureHandler?) -> OAuthSwiftRequestHandle? {
      var parameters = OAuthSwift.Parameters()
        parameters["client_id"] = self.consumer_key
        parameters["client_secret"] = self.consumer_secret
        parameters["refresh_token"] = refreshToken
        parameters["grant_type"] = "refresh_token"
        
        return requestOAuthAccessToken(withParameters: parameters, headers: headers, success: success, failure: failure)
    }
    
    fileprivate func requestOAuthAccessToken(withParameters parameters: OAuthSwift.Parameters, headers: OAuthSwift.Headers? = nil, success: @escaping TokenSuccessHandler, failure: FailureHandler?) -> OAuthSwiftRequestHandle? {
        let successHandler: OAuthSwiftHTTPRequest.SuccessHandler = { [unowned self]
            data, response in
            let responseJSON: Any? = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers)
            
            let responseParameters: OAuthSwift.Parameters
            
            if let jsonDico = responseJSON as? [String:Any] {
                responseParameters = jsonDico
            } else {
                let responseString = String(data: data, encoding: String.Encoding.utf8)!
                responseParameters = responseString.parametersFromQueryString()
            }
            
            guard let accessToken = responseParameters["access_token"] as? String else {
                let message =  NSLocalizedString("Could not get Access Token", comment: "Due to an error in the OAuth2 process, we couldn't get a valid token.")
                failure?(OAuthSwiftError.serverError(message: message))
                return
            }
            if let refreshToken = responseParameters["refresh_token"] as? String {
                self.client.credential.oauth_refresh_token = refreshToken.safeStringByRemovingPercentEncoding
            }

            if let expiresIn = responseParameters["expires_in"] as? String, let offset = Double(expiresIn)  {
                self.client.credential.oauth_token_expires_at = Date(timeInterval: offset, since: Date())
            } else if let expiresIn = responseParameters["expires_in"] as? Double {
                self.client.credential.oauth_token_expires_at = Date(timeInterval: expiresIn, since: Date())
            }
            
            self.client.credential.oauth_token = accessToken.safeStringByRemovingPercentEncoding
            success(self.client.credential, response, responseParameters)
        }

        if self.content_type == "multipart/form-data" {
            // Request new access token by disabling check on current token expiration. This is safe because the implementation wants the user to retrieve a new token.
            return self.client.postMultiPartRequest(self.access_token_url!, method: .POST, parameters: parameters, headers: headers, checkTokenExpiration: false, success: successHandler, failure: failure)
        } else {
            // special headers
            var headers: OAuthSwift.Headers? = nil
            if accessTokenBasicAuthentification {
 
                let authentification = "\(self.consumer_key):\(self.consumer_secret)".data(using: String.Encoding.utf8)
                if let base64Encoded = authentification?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
                    headers = ["Authorization": "Basic \(base64Encoded)"]
                }
            }
            if let access_token_url = access_token_url {
                // Request new access token by disabling check on current token expiration. This is safe because the implementation wants the user to retrieve a new token.
                return self.client.request(access_token_url, method: .POST, parameters: parameters, headers: headers, checkTokenExpiration: false, success: successHandler, failure: failure)
            }
            else {
                let message = NSLocalizedString("access token url not defined", comment: "access token url not defined with code type auth")
                failure?(OAuthSwiftError.configurationError(message: message))
                return nil
            }
        }
    }

    /**
     Convenience method to start a request that must be authorized with the previously retrieved access token.
     Since OAuth 2 requires support for the access token refresh mechanism, this method will take care to automatically
     refresh the token if needed such that the developer only has to be concerned about the outcome of the request.
     
     - parameter url:            The url for the request.
     - parameter method:         The HTTP method to use.
     - parameter parameters:     The request's parameters.
     - parameter headers:        The request's headers.
     - parameter onTokenRenewal: Optional callback triggered in case the access token renewal was required in order to properly authorize the request.
     - parameter success:        The success block. Takes the successfull response and data as parameter.
     - parameter failure:        The failure block. Takes the error as parameter.
     */
    open func startAuthorizedRequest(_ url: String, method: OAuthSwiftHTTPRequest.Method, parameters: OAuthSwift.Parameters, headers: OAuthSwift.Headers? = nil, onTokenRenewal: TokenRenewedHandler? = nil, success: @escaping OAuthSwiftHTTPRequest.SuccessHandler, failure: @escaping OAuthSwiftHTTPRequest.FailureHandler) -> OAuthSwiftRequestHandle? {
        // build request
        return self.client.request(url, method: method, parameters: parameters, headers: headers, success: success) { (error) in
            switch error {

            case OAuthSwiftError.tokenExpired:
                let _ = self.renewAccessToken(withRefreshToken: self.client.credential.oauth_refresh_token, headers: headers, success: { (credential, response, parameters) in
                    // We have successfully renewed the access token.
                    
                    // If provided, fire the onRenewal closure
                    if let renewalCallBack = onTokenRenewal {
                        renewalCallBack(credential)
                    }
                    
                    // Reauthorize the request again, this time with a brand new access token ready to be used.
                   let _ = self.startAuthorizedRequest(url, method: method, parameters: parameters, headers: headers, onTokenRenewal: onTokenRenewal, success: success, failure: failure)
                    }, failure: failure)
            default:
                failure(error)
            }
        }
    }
    
    open func authorize(deviceToken deviceCode: String, success: @escaping TokenRenewedHandler, failure: @escaping OAuthSwiftHTTPRequest.FailureHandler) -> OAuthSwiftRequestHandle? {
        var parameters = OAuthSwift.Parameters()
        parameters["client_id"] = self.consumer_key
        parameters["client_secret"] = self.consumer_secret
        parameters["code"] = deviceCode
        parameters["grant_type"] = "http://oauth.net/grant_type/device/1.0"
        
        return requestOAuthAccessToken(
            withParameters: parameters,
            success: { (credential, response, parameters) in
                success(credential)
            }, failure: failure
        )
    }

}
