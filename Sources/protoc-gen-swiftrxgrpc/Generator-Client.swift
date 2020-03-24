/*
 * Copyright 2018, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary

extension Generator {
  internal func printClient() {
    printServiceClientImplementation()
  }
  
  private func printServiceClientImplementation() {
    
    println("\(access) extension \(clientProtocolName) {")
    indent()
    indent()
    for method in service.methods {
      self.method = method
      let streamType = streamingType(self.method)
      switch streamType {
      case .unary:
        makeUnary(streamType)
      case .serverStreaming:
        makeServerStreaming(streamType)
      case .clientStreaming:
        makeClientStreaming(streamType)
      case .bidirectionalStreaming:
        makeBidirectionalStreaming()
      }
      println("}")
      println()
    }
    outdent()
    println("}")
  }
  
  private func printClientStreamingDetails() {
    println("/// Callers should use the `send` method on the returned object to send messages")
    println("/// to the server. The caller should send an `.end` after the final message has been sent.")
  }
  
  private func printParameters() {
    println("/// - Parameters:")
  }
  
  private func printRequestParameter() {
    println("///   - request: Request to send to \(method.name).")
  }
  
  private func printCallOptionsParameter() {
    println("///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.")
  }
  
  private func printHandlerParameter() {
    println("///   - handler: A closure called when each response is received from the server.")
  }
  
  fileprivate func makeUnary(_ streamType: StreamingType) {
    println(self.method.documentation(streamingType: streamType), newline: false)
    println("///")
    printParameters()
    printRequestParameter()
    printCallOptionsParameter()
    println("/// - Returns: A `(response: Single<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>)` with response, status and metadata (initial and trailing).")
    println("func \(methodFunctionName)Rx(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> (response: Single<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>) {")
    println("""
    let call = self.\(methodFunctionName)(request, callOptions: callOptions)
    return
        (response: .create{ single in
            call.response.whenFailure { single(.error($0)) }
            call.response.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }, status: .create { single in
            call.status.whenFailure { single(.error($0)) }
            call.status.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }, metadata: .create { observable in
            call.initialMetadata.whenFailure { observable.onError($0) }
            call.initialMetadata.whenSuccess { observable.onNext($0) }
            call.trailingMetadata.whenFailure { observable.onError($0) }
            call.trailingMetadata.whenSuccess { observable.onNext($0) }
            return Disposables.create()
        })
    """)
    println()
  }
  
  fileprivate func makeServerStreaming(_ streamType: StreamingType) {
    println(self.method.documentation(streamingType: streamType), newline: false)
    println("///")
    printParameters()
    printRequestParameter()
    printCallOptionsParameter()
    println("/// - Returns: A (response: Observable<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>) with response, status and metadata (initial and trailing).")
    println("func \(methodFunctionName)Rx(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> (response: Observable<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>) {")
    println("""
        let response = PublishSubject<\(methodOutputName)>()
        let statusSingle = PublishSubject<GRPCStatus>()
        let metadata = PublishSubject<HPACKHeaders>()
        
        let call = self.\(methodFunctionName)(request, callOptions: callOptions, handler: { message in
            response.onNext(message)
        })
        
        call.status.whenFailure { statusSingle.onError($0) }
        call.status.whenSuccess { statusSingle.onNext($0) }
        call.status.whenComplete {
            switch $0 {
            case .success(let status):
                switch status.code {
                case .ok:
                    response.onCompleted()
                default:
                    response.onError(status)
                }
            case .failure(let error):
                response.onError(error)
            }
        }
        call.initialMetadata.whenFailure { metadata.onError($0) }
        call.initialMetadata.whenSuccess { metadata.onNext($0) }
        call.trailingMetadata.whenFailure { metadata.onError($0) }
        call.trailingMetadata.whenSuccess { metadata.onNext($0) }
        
        return (response.asObservable(), statusSingle.asSingle(), metadata.asObservable())
    """)
  }
  
  fileprivate func makeClientStreaming(_ streamType: StreamingType) {
    println(self.method.documentation(streamingType: streamType), newline: false)
    println("///")
    printClientStreamingDetails()
    println("///")
    printParameters()
    println("///   - messages: `Observable<\(methodInputName)>` stream of the messages you want to send.")
    printCallOptionsParameter()
    println("/// - Returns: A `(response: Single<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>)` with response, status and metadata (initial and trailing).")
    println("func \(methodFunctionName)Rx(messages: Observable<\(methodInputName)>, callOptions: CallOptions? = nil) -> (response: Single<\(methodOutputName)>, status: Single<GRPCStatus>, metadata: Observable<HPACKHeaders>) {")
    println("""
        let call = self.\(methodFunctionName)(callOptions: callOptions)
        return (response: .create{ single in
            let disposable = messages.subscribe(onNext: {
              let message = call.sendMessage($0)
              message.whenFailure { single(.error($0)) }
            }, onCompleted: {
              let end = call.sendEnd()
              end.whenFailure { single(.error($0)) }
            })
            call.response.whenComplete {
              switch $0 {
              case .success(let response):
                single(.success(response))
              case .failure(let error):
                single(.error(error))
              }
            }
            return disposable
        }, status: .create { single in
            call.status.whenFailure { single(.error($0)) }
            call.status.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }, metadata: .create { observable in
            call.initialMetadata.whenFailure { observable.onError($0) }
            call.initialMetadata.whenSuccess { observable.onNext($0) }
            call.trailingMetadata.whenFailure { observable.onError($0) }
            call.trailingMetadata.whenSuccess { observable.onNext($0) }
            return Disposables.create()
        })
    """)
  }
  
  fileprivate func makeBidirectionalStreaming() {
    println("// NOT IMPLEMENTED YET")
  }
}

fileprivate extension StreamingType {
  var name: String {
    switch self {
    case .unary:
      return "Unary"
    case .clientStreaming:
      return "Client streaming"
    case .serverStreaming:
      return "Server streaming"
    case .bidirectionalStreaming:
      return "Bidirectional streaming"
    }
  }
}

extension MethodDescriptor {
  var documentation: String? {
    let comments = self.protoSourceComments(commentPrefix: "")
    return comments.isEmpty ? nil : comments
  }
  
  fileprivate func documentation(streamingType: StreamingType) -> String {
    let sourceComments = self.protoSourceComments()
    
    if sourceComments.isEmpty {
      return "/// \(streamingType.name) call to \(self.name)\n"  // comments end with "\n" already.
    } else {
      return sourceComments  // already prefixed with "///"
    }
  }
}
