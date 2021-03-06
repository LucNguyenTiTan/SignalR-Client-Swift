//
//  JSONHubProtocol.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 8/27/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import Foundation

public class JSONTypeConverter: TypeConverter {
    public func convertToWireType(obj: Any?) throws -> Any? {
        if isKnownType(obj: obj) || JSONSerialization.isValidJSONObject(obj: obj!) {
            return obj
        }

        throw SignalRError.unsupportedType
    }

    private func isKnownType(obj: Any?) -> Bool {
        return obj == nil ||
            obj is Int || obj is Int? || obj is [Int] || obj is [Int?] ||
            obj is Double || obj is Double? || obj is [Double] || obj is [Double?] ||
            obj is String || obj is String? || obj is [String] || obj is [String?] ||
            obj is Bool || obj is Bool? || obj is [Bool] || obj is [Bool?];
    }

    public func convertFromWireType<T>(obj:Any?, targetType: T.Type) throws -> T? {
        if obj == nil {
            return nil
        }

        if let converted = obj as? T? {
            return converted
        }

        throw SignalRError.unsupportedType
    }
}

public class JSONHubProtocol: HubProtocol {
    private let recordSeparator = "\u{1e}"
    public let typeConverter: TypeConverter
    public let name = "json"
    public let type = ProtocolType.Text

    public convenience init() {
        self.init(typeConverter: JSONTypeConverter())
    }

    public init(typeConverter: TypeConverter) {
        self.typeConverter = typeConverter
    }

    public func parseMessages(input: Data) throws -> [HubMessage] {
        let dataString = String(data: input, encoding: .utf8)!

        var hubMessages = [HubMessage]()

        if let range = dataString.range(of: recordSeparator, options: .backwards) {
            let messages = dataString.substring(to: range.lowerBound).components(separatedBy: recordSeparator)
            for message in messages {
                hubMessages.append(try createHubMessage(payload: message))
            }
        }

        return hubMessages
    }

    private func createHubMessage(payload: String) throws -> HubMessage {
        // TODO: try to avoid double conversion (Data -> String -> Data)
        let json = try JSONSerialization.jsonObject(with: payload.data(using: .utf8)!)

        if let message = json as? NSDictionary, let rawMessageType = message.object(forKey: "type") as? Int, let messageType = MessageType(rawValue: rawMessageType) {
            switch messageType {
            case .Invocation:
                return try createInvocationMessage(message: message)
            case .StreamItem:
                return try createStreamItemMessage(message: message)
            case .Completion:
                return try createCompletionMessage(message: message)
            }
        }

        throw SignalRError.unknownMessageType
    }

    private func createInvocationMessage(message: NSDictionary) throws -> InvocationMessage {
        let invocationId = try getInvocationId(message: message)

        guard let target = message.value(forKey: "target") as? String else {
            throw SignalRError.invalidMessage
        }
        
        let nonBlocking = (message.value(forKey: "nonBlocking") as? Bool) ?? false

        let arguments = message.object(forKey: "arguments") as? NSArray

        // TODO: handle argument type conversion/resolution
        return InvocationMessage(invocationId: invocationId, target: target, arguments: arguments as? [Any?] ?? [], nonBlocking: nonBlocking)
    }

    private func createStreamItemMessage(message: NSDictionary) throws -> StreamItemMessage {
        let invocationId = try getInvocationId(message: message)

        // TODO: handle stream item
        return StreamItemMessage(invocationId: invocationId, item: nil)
    }

    private func createCompletionMessage(message: NSDictionary) throws -> CompletionMessage {
        let invocationId = try getInvocationId(message: message)
        if let error = message.value(forKey: "error") as? String {
            return CompletionMessage(invocationId: invocationId, error: error)
        }

        if let result = message.value(forKey: "result") {
            return CompletionMessage(invocationId: invocationId, result: result is NSNull ? nil : result)
        }

        return CompletionMessage(invocationId: invocationId)
    }

    private func getInvocationId(message: NSDictionary) throws -> String {
        guard let invocationId = message.value(forKey: "invocationId") as? String else {
            throw SignalRError.invalidMessage
        }

        return invocationId
    }

    public func writeMessage(message: HubMessage) throws -> Data {
        guard message.messageType == .Invocation else {
            throw SignalRError.invalidOperation(message: "Unexpected MessageType.")
        }

        let invocationMessage = message as! InvocationMessage
        let invocationJSONObject : [String: Any] = [
            "type": invocationMessage.messageType.rawValue,
            "invocationId": invocationMessage.invocationId,
            "target": invocationMessage.target,
            "arguments": try invocationMessage.arguments.map{ arg -> Any? in
                return try typeConverter.convertToWireType(obj: arg)
            },
            "nonBlocking": invocationMessage.nonBlocking]

        var payload = try JSONSerialization.data(withJSONObject: invocationJSONObject)
        payload.append(recordSeparator.data(using: .utf8)!)
        return payload
    }
}
