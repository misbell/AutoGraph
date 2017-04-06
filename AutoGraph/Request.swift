import Crust
import Foundation
import JSONValueRX

public protocol Request {
    /// The `Mapping` used to map from the returned JSON payload to a concrete type
    /// `Mapping.MappedObject`.
    associatedtype Mapping: Crust.Mapping
    
    /// The returned type for the request.
    /// E.g if the requests returns an array then change to `[Mapping.MappedObject]`.
    associatedtype SerializedObject = Mapping.MappedObject
    
    associatedtype Query: GraphQLQuery
    
    /// If the `SerializedObject`(s) cannot be passed across threads, then we'll use this to transform
    /// the objects as they are passed from the background to the main thread.
    associatedtype ThreadAdapterType: ThreadAdapter
    
    /// The query to be sent to GraphQL.
    var query: Query { get }
    
    /// The mapping to use when mapping JSON into the a concrete type.
    ///
    /// **WARNING:**
    ///
    /// `mapping` does NOT execute on the main thread. It's important that any `Adapter`
    /// used by `mapping` establishes it's own connection to the DB from within `mapping`.
    ///
    /// Additionally, the mapped data (`Mapping.MappedObject`) is assumed to be safe to pass
    /// across threads unless it inherits from `ThreadUnsafe`.
    var mapping: Binding<Mapping> { get }
    
    /// Our `ThreadAdapter`. It's `typealias BaseType` must be a the same type or a super type of `Mapping.MappedObject`
    /// or an error will be thrown at runtime.
    var threadAdapter: ThreadAdapterType? { get }
    
    /// Called at the moment before the request will be sent from the `Client`.
    func willSend() throws
    
    /// Called as soon as the http request finishs.
    func didFinishRequest(response: HTTPURLResponse?, json: JSONValue) throws
    
    /// Called right before calling the completion handler for the sent request, i.e. at the end of the lifecycle.
    func didFinish(result: AutoGraphQL.Result<SerializedObject>) throws
}

extension Int: AnyMappable { }
class VoidMapping: AnyMapping {
    typealias AdapterKind = AnyAdapterImp<MappedObject>
    typealias MappedObject = Int
    func mapping(toMap: inout Int, context: MappingContext) { }
}

// TODO: We should support non-equatable collections.
// TOOD: We should better apply currying and futures to clean some of this up.
public enum ObjectBinding<M: Mapping, CM: Mapping, C: RangeReplaceableCollection,
    T: ThreadAdapter>
where C.Iterator.Element == CM.MappedObject, CM.MappedObject: Equatable {
    
    case object(mappingBinding: () -> Binding<M>, threadAdapter: T?, completion: RequestCompletion<M.MappedObject>)
    case collection(mappingBinding: () -> Binding<CM>, threadAdapter: T?, completion: RequestCompletion<C>)
}

extension Request
    where SerializedObject: RangeReplaceableCollection,
    SerializedObject.Iterator.Element == Mapping.MappedObject,
    Mapping.MappedObject: Equatable {
    
    func generateBinding(completion: @escaping RequestCompletion<SerializedObject>) -> ObjectBinding<Mapping, Mapping, SerializedObject, ThreadAdapterType> {
        return ObjectBinding<Mapping, Mapping, SerializedObject, ThreadAdapterType>.collection(mappingBinding: { self.mapping }, threadAdapter: self.threadAdapter, completion: completion)
    }
}

extension Request where SerializedObject == Mapping.MappedObject {
    func generateBinding(completion: @escaping RequestCompletion<Mapping.MappedObject>) -> ObjectBinding<Mapping, VoidMapping, Array<Int>, ThreadAdapterType> {
        return ObjectBinding<Mapping, VoidMapping, Array<Int>, ThreadAdapterType>.object(mappingBinding: { self.mapping }, threadAdapter: threadAdapter, completion: completion)
    }
}
