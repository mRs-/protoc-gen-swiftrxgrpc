import Foundation
import GRPC
import NIOHPack
import RxSwift

public enum ClientResult<Response> {
    case initial(metadata: HPACKHeaders)
    case finished(result: Result<Response, GRPCStatus>, metadata: (initial: HPACKHeaders?, trailing: HPACKHeaders?))
}

extension RxSwift.Single {
    func startWithNil() -> Observable<Element?> {
        asObservable()
            .map { $0 as Element? }
            .startWith(nil)
    }
}
