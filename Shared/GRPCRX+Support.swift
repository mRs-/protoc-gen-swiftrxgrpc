import Foundation
import GRPC
import NIOHPACK
import RxSwift

public typealias ClientOK = Void
public enum ClientError: Swift.Error {
    case status(GRPCStatus)
    case other(Swift.Error)
}

public enum ClientResult<Response> {
    case initial(metadata: HPACKHeaders)
    case finished(result: Result<Response, ClientError>, metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?))

    public func mapFinished<NewResponse>(_ transform: (Result<Response, ClientError>) -> Result<NewResponse, ClientError>) -> ClientResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(result: result, metadata: metadata):
            return .finished(result: transform(result), metadata: metadata)
        }
    }

    public func flatMapFinished<NewResponse>(
        _ transform: (Result<Response, ClientError>,
                      _ metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?)) -> ClientResult<NewResponse>)
        -> ClientResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(result: result, metadata: metadata):
            return transform(result, metadata)
        }
    }

    public var initialMetada: HPACKHeaders? {
        switch self {
        case let .initial(metadata: metadata):
            return metadata
        case .finished(result: _, metadata: let metadata):
            return metadata.initial
        }
    }

    public var trailingMetadata: HPACKHeaders? {
        switch self {
        case .finished(result: _, metadata: let metadata):
            return metadata.trailing
        case .initial:
            return nil
        }
    }

    public var status: GRPCStatus? {
        switch self {
        case .finished(result: let result, metadata: _):
            switch result {
            case let .failure(status):
                switch status {
                case let .status(grpcStatus):
                    return grpcStatus
                case .other:
                    return nil
                }
            case .success:
                return nil
            }
        case .initial:
            return nil
        }
    }

    public var result: Result<Response, ClientError>? {
        switch self {
        case .finished(result: let result, metadata: _):
            return result
        case .initial(metadata: _):
            return nil
        }
    }
}

public enum ClientStreamingResult<Response> {
    case initial(metadata: HPACKHeaders)
    case streaming(response: Response)
    case finished(result: Result<ClientOK, ClientError>, metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?))

    func mapStreaming<NewResponse>(_ transform: (Response) -> NewResponse) -> ClientStreamingResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(result: status, metadata: metadata):
            return .finished(result: status, metadata: metadata)
        case let .streaming(response: response):
            return .streaming(response: transform(response))
        }
    }

    func flatMapStreaming<NewResponse>(_ transform: (Response) -> ClientStreamingResult<NewResponse>) -> ClientStreamingResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(result: status, metadata: metadata):
            return .finished(result: status, metadata: metadata)
        case let .streaming(response: response):
            return transform(response)
        }
    }

    public var initialMetada: HPACKHeaders? {
        switch self {
        case let .initial(metadata: metadata):
            return metadata
        case .finished(result: _, metadata: let metadata):
            return metadata.initial
        case .streaming:
            return nil
        }
    }

    public var trailingMetadata: HPACKHeaders? {
        switch self {
        case .finished(result: _, metadata: let metadata):
            return metadata.trailing
        default:
            return nil
        }
    }

    public var status: GRPCStatus? {
        switch self {
        case .finished(result: let status, metadata: _):
            switch status {
            case .success:
                return .ok
            case let .failure(error):
                switch error {
                case let .status(grpcStatus):
                    return grpcStatus
                case .other:
                    return nil
                }
            }
        default:
            return nil
        }
    }

    public var response: Response? {
        switch self {
        case let .streaming(response: response):
            return response
        case .initial, .finished:
            return nil
        }
    }
}

extension RxSwift.Single {
    func startWithNil() -> Observable<Element?> {
        asObservable()
            .map { $0 as Element? }
            .startWith(nil)
    }
}
