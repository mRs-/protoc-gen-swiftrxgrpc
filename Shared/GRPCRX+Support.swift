import Foundation
import GRPC
import NIOHPACK
import RxSwift

public enum ClientResult<Response> {
    case initial(metadata: HPACKHeaders)
    case finished(result: Result<Response, GRPCStatus>, metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?))

    public func mapFinished<NewResponse>(_ transform: (Result<Response, GRPCStatus>) -> Result<NewResponse, GRPCStatus>) -> ClientResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(result: result, metadata: metadata):
            return .finished(result: transform(result), metadata: metadata)
        }
    }

    public func flatMapFinished<NewResponse>(
        _ transform: (Result<Response, GRPCStatus>,
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
                return status
            case .success:
                return nil
            }
        case .initial:
            return nil
        }
    }

    public var result: Result<Response, GRPCStatus>? {
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
    case finished(status: GRPCStatus, metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?))

    func mapStreaming<NewResponse>(_ transform: (Response) -> NewResponse) -> ClientStreamingResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(status: status, metadata: metadata):
            return .finished(status: status, metadata: metadata)
        case let .streaming(response: response):
            return .streaming(response: transform(response))
        }
    }

    func flatMapStreaming<NewResponse>(_ transform: (Response) -> ClientStreamingResult<NewResponse>) -> ClientStreamingResult<NewResponse> {
        switch self {
        case let .initial(metadata: headers):
            return .initial(metadata: headers)
        case let .finished(status: status, metadata: metadata):
            return .finished(status: status, metadata: metadata)
        case let .streaming(response: response):
            return transform(response)
        }
    }

    public var initialMetada: HPACKHeaders? {
        switch self {
        case let .initial(metadata: metadata):
            return metadata
        case .finished(status: _, metadata: let metadata):
            return metadata.initial
        case .streaming:
            return nil
        }
    }

    public var trailingMetadata: HPACKHeaders? {
        switch self {
        case .finished(status: _, metadata: let metadata):
            return metadata.trailing
        default:
            return nil
        }
    }

    public var status: GRPCStatus? {
        switch self {
        case .finished(status: let status, metadata: _):
            return status
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
