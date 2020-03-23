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
    println("/// - Returns: A `Single<\(methodOutputName)>` with metadata, status and response.")
    println("func \(methodFunctionName)Rx(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> Single<\(methodOutputName)> {")
    indent()
    println("Single.create { single in ")
    indent()
    println("let future = self.\(methodFunctionName)(request, callOptions: callOptions)")
    println("future.response.whenFailure { single(.error($0)) }")
    println("future.response.whenSuccess {")
    indent()
    println("single(.success($0))")
    outdent()
    println("}")
    outdent()
    println("return Disposables.create()")
    println("}")
    outdent()
  }
  
  fileprivate func makeServerStreaming(_ streamType: StreamingType) {
    println(self.method.documentation(streamingType: streamType), newline: false)
    println("///")
    printParameters()
    printRequestParameter()
    printCallOptionsParameter()
    println("/// - Returns: A `Observable<\(methodOutputName)>` with the metadata and status.")
    println("func \(methodFunctionName)Rx(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> Observable<\(methodOutputName)> {")
    indent()
    println("Observable.create { observer in")
    indent()
    println("let call = self.receiveTranslatedDocument(request, callOptions: callOptions) { chunk in")
    println("observer.onNext(chunk)")
    outdent()
    println("}")
    println("call.status.whenComplete {")
    indent()
    println("switch $0 {")
    println("case .success(let status):")
    indent()
    println("switch status.code {")
    println("case .ok:")
    indent()
    println("observer.onCompleted()")
    outdent()
    println("default:")
    indent()
    println("observer.onError(status)")
    outdent()
    println("}")
    outdent()
    println("case .failure(let error):")
    indent()
    println("observer.onError(error)")
    outdent()
    println("}")
    outdent()
    println("}")
    println("return Disposables.create()")
    outdent()
    println("}")
    outdent()
  }
  
  fileprivate func makeClientStreaming(_ streamType: StreamingType) {
    println(self.method.documentation(streamingType: streamType), newline: false)
    println("///")
    printClientStreamingDetails()
    println("///")
    printParameters()
    println("///   - messages: `Observable<\(methodInputName)>` stream of the messages you want to send.")
    printCallOptionsParameter()
    println("/// - Returns: A `Single<\(methodOutputName)>` with the metadata, status and response.")
    println("func \(methodFunctionName)Rx(messages: Observable<\(methodInputName)>, callOptions: CallOptions? = nil) -> Single<\(methodOutputName)> {")
    indent()
    println("Single.create { single -> Disposable in")
    indent()
    println("let future = self.\(methodFunctionName)(callOptions: callOptions)")
    println("let disposable = messages.subscribe(onNext: {")
    indent()
    println("let message = future.sendMessage($0)")
    println("message.whenFailure { single(.error($0)) }")
    outdent()
    println("}, onCompleted: {")
    indent()
    println("let end = future.sendEnd()")
    println("end.whenFailure { single(.error($0)) }")
    outdent()
    println("})")
    println("future.response.whenComplete {")
    indent()
    println("switch $0 {")
    println("case .success(let response):")
    indent()
    println("single(.success(response))")
    outdent()
    println("case .failure(let error):")
    indent()
    println("single(.error(error))")
    outdent()
    println("}")
    outdent()
    println("}")
    println("return disposable")
    outdent()
    println("}")
    outdent()
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
