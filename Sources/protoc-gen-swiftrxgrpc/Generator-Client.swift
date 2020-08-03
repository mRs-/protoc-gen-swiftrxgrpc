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
    println("/// - Returns: Observable ClientResult<\(methodOutputName)> with initialMetadata and finished call.")
    println("func rx\(methodFunctionName.capitalizingFirstLetter())(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> Observable<ClientResult<\(methodOutputName)>> {")
    println("""
    let call = \(methodFunctionName)(request, callOptions: callOptions)
        
        let response = Single<\(methodOutputName)>.create { single in
            call.response.whenFailure { single(.error($0)) }
            call.response.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let initialMetadata = Single<HPACKHeaders>.create { single in
            call.initialMetadata.whenFailure { single(.error($0)) }
            call.initialMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let trailingMetadata = Single<HPACKHeaders>.create { single in
            call.trailingMetadata.whenFailure { single(.error($0)) }
            call.trailingMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let status = Single<GRPCStatus>.create { single in
            call.status.whenFailure { single(.error($0)) }
            call.status.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }
        
        var completed = false
        
        return Observable
            .combineLatest(initialMetadata.startWithNil(),
                           response.startWithNil(),
                           Observable.zip(status.startWithNil(), trailingMetadata.startWithNil()))
            .flatMap { tuple -> Observable<ClientResult<\(methodOutputName)>> in
                switch tuple {
                case (let .some(initial), nil, (nil, nil)):
                    return .just(.initial(metadata: initial))
                case let (initial, .some(response), (.some(status), trailing)) where status.code == .ok:
                    return .just(.finished(result: .success(response), metadata: (initial, trailing)))
                case let (initial, _, (.some(status), trailing)):
                    return .just(.finished(result: .failure(.status(status)), metadata: (initial, trailing)))
                default:
                    return .empty()
                }
            }
            .catchError{ error in
                guard let grpcStatus = error as? GRPCStatus else {
                    return .just(.finished(result: .failure(.other(error)),
                    metadata: (initial: nil, trailing: nil)))
                    
                }
                return .just(.finished(result: .failure(.status(grpcStatus)),
                metadata: (initial: nil, trailing: nil)))
            }
            .do(onCompleted: {
                completed = true
            }, onDispose: {
                if !completed {
                    call.cancel(promise: nil)
                }
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
    println("/// - Returns: Observable ClientStreamingResult<\(methodOutputName)> with initialMetadata and finished call.")
    println("func rx\(methodFunctionName.capitalizingFirstLetter())(_ request: \(methodInputName), callOptions: CallOptions? = nil) -> Observable<ClientStreamingResult<\(methodOutputName)>> {")
    println("""
        let response = PublishSubject<\(methodOutputName)?>()
        let call = \(methodFunctionName)(request, callOptions: callOptions) { message in
            response.onNext(message)
        }

        let status = Single<GRPCStatus>.create { single in
            call.status.whenFailure {
                single(.error($0))
                response.onError($0)
            }
            call.status.whenSuccess {
                single(.success($0))
                response.onCompleted()
            }
            return Disposables.create()
        }

        let initialMetadata = Single<HPACKHeaders>.create { single in
            call.initialMetadata.whenFailure { single(.error($0)) }
            call.initialMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let trailingMetadata = Single<HPACKHeaders>.create { single in
            call.trailingMetadata.whenFailure { single(.error($0)) }
            call.trailingMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        var completed = false
        
        return Observable
            .combineLatest(status.startWithNil(),
                           response.startWith(nil),
                           initialMetadata.startWithNil(),
                           trailingMetadata.startWithNil())
            .flatMap { tuple -> Observable<ClientStreamingResult<\(methodOutputName)>> in
                switch tuple {
                case (nil, nil, let .some(initial), nil):
                    return .just(.initial(metadata: initial))
                case let (.some(_), _, initial, trailing):
                    return .just(.finished(result: .success(ClientOK()), metadata: (initial, trailing)))
                case let (.none, .some(response), _, .none):
                    return .just(.streaming(response: response))
                default:
                    return .empty()
                }
            }
            .catchError{ error in
                guard let grpcStatus = error as? GRPCStatus else {
                    return .just(.finished(result: .failure(.other(error)),
                                           metadata: (initial: nil, trailing: nil)))
                }
                return .just(.finished(result: .failure(.status(grpcStatus)),
                                       metadata: (initial: nil, trailing: nil)))
            }
            .do(onCompleted: {
                completed = true
            }, onDispose: {
                if !completed {
                    call.cancel(promise: nil)
                }
            })
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
    println("/// - Returns: Observable ClientResult<\(methodOutputName)> with initialMetadata and finished call.")
    println("func rx\(methodFunctionName.capitalizingFirstLetter())(messages: Observable<\(methodInputName)>, callOptions: CallOptions? = nil) -> Observable<ClientResult<\(methodOutputName)>> {")
    println("""
        let call = \(methodFunctionName)(callOptions: callOptions)
        let status = Single<GRPCStatus>.create { single in
            call.status.whenFailure { single(.error($0)) }
            call.status.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let response = Single<\(methodOutputName)>.create { single in
            let disposable = messages.subscribe(onNext: {
                let message = call.sendMessage($0)
                message.whenFailure { single(.error($0)) }
            }, onError: { error in
                _ = call.sendEnd()
                single(.error(error))
            }, onCompleted: {
                let end = call.sendEnd()
                end.whenFailure { single(.error($0)) }
            })
            call.response.whenFailure { single(.error($0)) }
            call.response.whenSuccess { single(.success($0)) }
            return disposable
        }

        let initialMetadata = Single<HPACKHeaders>.create { single in
            call.initialMetadata.whenFailure { single(.error($0)) }
            call.initialMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        let trailingMetadata = Single<HPACKHeaders>.create { single in
            call.trailingMetadata.whenFailure { single(.error($0)) }
            call.trailingMetadata.whenSuccess { single(.success($0)) }
            return Disposables.create()
        }

        var completed = false
        
        return Observable
            .combineLatest(initialMetadata.startWithNil(),
                           response.startWithNil(),
                           Observable.zip(status.startWithNil(), trailingMetadata.startWithNil()))
            .flatMap { tuple -> Observable<ClientResult<\(methodOutputName)>> in
                switch tuple {
                case (let .some(initial), nil, (nil, nil)):
                    return .just(.initial(metadata: initial))
                case let (initial, .some(response), (.some(status), trailing)) where status.code == .ok:
                    return .just(.finished(result: .success(response), metadata: (initial, trailing)))
                case let (initial, _, (.some(status), trailing)):
                    return .just(.finished(result: .failure(.status(status)), metadata: (initial, trailing)))
                default:
                    return .empty()
                }
            }
            .catchError{ error in
                guard let grpcStatus = error as? GRPCStatus else {
                    return .just(.finished(result: .failure(.other(error)),
                    metadata: (initial: nil, trailing: nil)))
                    
                }
                return .just(.finished(result: .failure(.status(grpcStatus)),
                metadata: (initial: nil, trailing: nil)))
            }
            .do(onCompleted: {
                completed = true
            }, onDispose: {
                if !completed {
                    call.cancel(promise: nil)
                }
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

private extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}
