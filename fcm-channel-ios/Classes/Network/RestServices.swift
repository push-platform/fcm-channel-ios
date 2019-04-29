//
//  RestServices.swift
//  fcm-channel-ios
//
//  Created by Alexandre Azevedo on 03/04/19.
//

import Foundation
import Alamofire
import AlamofireObjectMapper
import ObjectMapper

class RestServices {
    static var shared = RestServices()

    private var headers: HTTPHeaders {
        let token = FCMChannelSettings.shared.token
        return ["Authorization": "Token \(token)",
            "Accept": "application/json"]
    }

   private init() {}

    // MARK: - Flow
   func getFlowDefinition(_ flowUuid: String, completion: @escaping (FCMChannelFlowDefinition?) -> Void) {

        let url = "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)definitions.json?flow=\(flowUuid)"

        Alamofire.request(url, method: .get,
                   encoding: JSONEncoding.default,
                   headers: headers).responseObject { (response: DataResponse<FCMChannelFlowDefinition>) in

            switch response.result {

            case .failure(let error):
                print(error.localizedDescription)
                completion(nil)

            case .success(let value):
                completion(value)
            }
        }
    }

    func getFlowRuns(_ contact: FCMChannelContact, completion: @escaping ([FCMChannelFlowRun]?) -> Void) {

        guard let contactId = contact.uuid, let minimumDate = getMinimumDate() else {
            completion(nil)
            return
        }

        let afterDate = FCMChannelDateUtil.dateFormatter(minimumDate)
        let url = "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)runs.json?contact=\(contactId)&after=\(afterDate)"

        Alamofire.request(url,
                   method: .get,
                   encoding: JSONEncoding.default,
                   headers: headers).responseObject { (response: DataResponse<APIResponse<FCMChannelFlowRun>>) in

                    switch response.result {

                    case .failure(let error):
                        print(error.localizedDescription)
                        completion(nil)

                    case .success(let value):
                        if let results = value.results, !results.isEmpty {
                            completion(value.results)
                        } else {
                            completion(nil)
                        }
                    }
        }
    }

    // MARK: - Messages
    func sendReceivedMessage(_ contact: FCMChannelContact, message: String, completion:@escaping (_ success: Bool) -> Void) {
        if let token = contact.fcmToken, let urn = contact.urns.first {
            let handlerUrl = FCMChannelSettings.shared.handlerURL
            let channel = FCMChannelSettings.shared.channel

            let params = [
                "from": urn.replacingOccurrences(of: "fcm:", with: ""),
                "msg": message,
                "fcm_token": token
            ]

            let url = "\(handlerUrl)/receive/\(channel)/"
            Alamofire.request(url, method: .post, parameters: params).responseString { (response) in

                switch response.result {

                case .failure(let error):
                    print("error \(String(describing: error.localizedDescription))")
                    completion(false)

                case .success(let value):
                    print(value)
                    completion(true)
                }
            }
        }
    }

    func loadMessages(contact: FCMChannelContact, completion: @escaping (_ messages: [FCMChannelMessage]?) -> Void ) {

        guard let contactId = contact.uuid else {
            completion(nil)
            return
        }

        let url = "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)messages.json?contact=\(contactId)"

        Alamofire.request(url, method: .get,
                   encoding: JSONEncoding.default,
                   headers: headers).responseObject { (response: DataResponse<APIResponse<FCMChannelMessage>>) in

                    switch response.result {

                    case .failure(let error):
                        print(error.localizedDescription)
                        completion(nil)

                    case .success(let value):
                        if let results = value.results, !results.isEmpty {
                            completion(value.results)
                        } else {
                            completion(nil)
                        }
                    }
        }
    }

    func loadMessageByID(_ messageID: Int, completion: @escaping (_ message: FCMChannelMessage?) -> Void ) {

        let url = "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)messages.json?id=\(messageID)"

        Alamofire.request(url, method: .get, encoding: JSONEncoding.default, headers: headers).responseObject { (response: DataResponse<APIResponse<FCMChannelMessage>>) in

            switch response.result {

            case .failure(let error):
                print(error.localizedDescription)
                completion(nil)

            case .success(let value):
                if let results = value.results, !results.isEmpty {
                    completion(results.first)
                } else {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Contact

    private func loadContact(fromURL url: URL, completion: @escaping (_ contact: FCMChannelContact?) -> Void) {
        let request = Alamofire.request(url,
                                        method: .get,
                                        encoding: URLEncoding.default,
                                        headers: headers)
            .responseJSON { (response: DataResponse<Any>) in

                if let response = response.result.value as? [String: Any] {
                    guard let result = (response["results"] as? [[String: Any]])?.first else {
                        completion(nil)
                        return
                    }

                    let contact = Mapper<FCMChannelContact>().map(JSON: result)
                    if contact?.fcmToken == nil {
                        contact?.fcmToken = ""
                    }
                    completion(contact)
                }
        }

        debugPrint(request)
    }

    func loadContact(fromUUID uuid: String, completion: @escaping (_ contact: FCMChannelContact?) -> Void) {
        let url: URL! = URL(string: "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)contacts.json?uuid=\(uuid)")
        loadContact(fromURL: url, completion: completion)
    }

    func loadContact(fromUrn urn: String, completion: @escaping (_ contact: FCMChannelContact?) -> Void) {
        let url: URL! = URL(string: "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)contacts.json?urn=\(urn)")
        loadContact(fromURL: url, completion: completion)
    }

    func fetchContact(completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let contact = FCMChannelContact.current(), let urn = contact.urn else {
            completion(false, nil)
            return
        }

        let url = "\(FCMChannelSettings.shared.url)\(FCMChannelSettings.shared.V2)contacts.json?urn=fcm:\(urn)"

        Alamofire.request(url, method: .get, headers: headers).responseJSON { (response: DataResponse<Any>) in

            if let responseValue = response.result.value as? [String: Any] {
                guard let results = responseValue["results"] as? [[String: Any]], results.count > 0 else {
                    completion(false, nil)
                    return
                }

                guard let data = results.first else {
                    completion(false, nil)
                    return
                }

                var fcmToken = ""
                if let urns = data["urns"] as? [String] {
                    let filtered = urns.filter {($0.contains("fcm"))}
                    if !filtered.isEmpty {
                        fcmToken = String(filtered.first?.dropFirst(4) ?? "")
                    }
                }

                guard let contact = Mapper<FCMChannelContact>().map(JSONObject: data) else {
                    completion(false, response.result.error)
                    return
                }
                contact.urn = fcmToken

                FCMChannelContact.setActive(contact: contact)
                completion(true, nil)
            } else if let error = response.result.error {
                completion(false, error)
            }
        }
    }

    func registerFCMContact(urn: String, name: String, fcmToken: String, contactUuid: String? = nil, completion: @escaping (_ uuid: String?, _ error: Error?) -> Void) {

        let url = "\(FCMChannelSettings.shared.handlerURL)/register/\(FCMChannelSettings.shared.channel)/"

        var params = ["urn": urn.replacingOccurrences(of: "fcm:", with: ""),
                      "name": name,
                      "fcm_token": fcmToken] as [String: Any]

        if let contactUuid = contactUuid {
            params["contact_uuid"] = contactUuid
        }

        Alamofire.request(url, method: .post, parameters: params).responseJSON( completionHandler: { response in

            switch response.result {

            case .failure(let error):
                print("error \(String(describing: error.localizedDescription))")
                completion(nil, error)

            case .success(let value):
                if let response = value as? [String: String], let uuid = response["contact_uuid"] {
                    completion(uuid, nil)
                } else {
                    completion(nil, nil)
                }
            }
        })
    }

    // MARK: - Class Functions
    private func getMinimumDate() -> Date? {
        let date = Date()
        let gregorian = Calendar(identifier: Calendar.Identifier.gregorian)
        var offsetComponents = DateComponents()
        offsetComponents.month = -1
        return (gregorian as NSCalendar).date(byAdding: offsetComponents, to: date, options: [])
    }
}
