//
//  SSCCE for SO.swift
//  Shared Library
//
//  Created by Ben Leggiero on 2017-12-15.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Foundation



// MARK: - Client

public class SscceClient: ClientProtocol {
    
    public init() {}
    
    public func send(data: Data,
                     to address: inout sockaddr_in,
                     andReceive responseHandler: @escaping ServerResponseHandler) throws {
        
        var context = ClientDelegate(dataToSend: data, serverResponseHandler: responseHandler).wrappedInContext()
        
        guard let socket = CFSocket.create(protocolFamily: PF_INET,
                                           socketType: SOCK_STREAM,
                                           protocol: IPPROTO_TCP,
                                           callBackTypes: [.acceptCallBack, .dataCallBack],
                                           callout: basicCallout,
                                           context: &context)
            else {
            throw FailedToCreateSocket(errno: errno)
        }
        
        try socket.connect(to: Data(rawBytesIn: &address) as CFData)
    }
}



class ClientDelegate: SscceSocketDelegate {
    
    let dataToSend: Data
    let serverResponseHandler: SscceClient.ServerResponseHandler
    
    init(dataToSend: Data,
         serverResponseHandler: @escaping SscceClient.ServerResponseHandler) {
        self.dataToSend = dataToSend
        self.serverResponseHandler = serverResponseHandler
    }
    
    public func readData(from socket: CFSocket) {
        print("Ready to read from socket")
        
        let (inputStream, _) = socket.createStreamPair()
        
        inputStream.open()
        defer {
            inputStream.close()
        }
        
        do {
            let data = try inputStream.readToData()
            serverResponseHandler(.some(data))
        }
        catch let error {
            assertionFailure("Failed to read from input stream: \(error)")
            serverResponseHandler(.none(error))
        }
    }
    
    
    public func acceptNewConnection(from socket: CFSocket, childSocketHandle: CFSocketNativeHandle) {
        print("Connected to socket #\(childSocketHandle)")
    }
    
    
    public func dataCallback(socket: CFSocket, readData: Data) {
        print("Got data from server:", String(data: readData, encoding: .utf8) ?? readData.description)
    }
    
    
    public func socketDidConnect(socket: CFSocket, errorCode: Int32?) {
        if let errorCode = errorCode,
            errorCode != 0 {
            print("Socket failed to connect:", String(errno: errorCode))
            serverResponseHandler(.none(FailedToConnect(errno: errorCode)))
        }
        else {
            print("Socket connected")
        }
    }
    
    
    public func writeCallback(socket: CFSocket) {
        print("Ready to write to socket")
        
        let (_, outputStream) = socket.createStreamPair()
        
        outputStream.open()
        defer {
            outputStream.close()
        }
        
        do {
            try outputStream.write(data: dataToSend)
        }
        catch let error {
            assertionFailure("Failed to write to output stream: \(error)")
        }
    }
}



// MARK: - Server

public class SscceServer: ServerProtocol {
    
    public typealias RequestHandler = (DescriptiveOptional<Data>) -> Void
    public typealias ResponseHandler = () -> Data?
    
    var address: sockaddr_in
    private let requestHandler: RequestHandler
    private let responseHandler: ResponseHandler
    
    private var cfSocket: CFSocket!
    
    
    public init(address: sockaddr_in, clientRequestHandler: @escaping RequestHandler, clientResponseHandler: @escaping ResponseHandler) {
        self.address = address
        self.requestHandler = clientRequestHandler
        self.responseHandler = clientResponseHandler
    }
    
    
    public func start() throws {
        var context = self.wrappedInContext()
        cfSocket = CFSocket.create(protocolFamily: PF_INET,
                                   socketType: SOCK_STREAM,
                                   protocol: IPPROTO_TCP,
                                   callBackTypes: [.acceptCallBack, .dataCallBack],
                                   callout: basicCallout,
                                   context: &context)
        
        CFSocketSetSocketFlags(cfSocket, kCFSocketCloseOnInvalidate | kCFSocketAutomaticallyReenableReadCallBack)
        
        guard cfSocket != nil else {
            throw FailedToCreateSocket(errno: errno)
        }
        
        try cfSocket.bind(to: Data(rawBytesIn: &address) as CFData)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocket, 0), .defaultMode)
        
//        let (inputStream, outputStream) = cfSocket.createStreamPair()
//
//        while true {
//            do {
//                let readData = try inputStream.readToData()
//                print("Read data:", String(data: readData, encoding: .utf8) ?? readData.description)
//            }
//            catch let error {
//                print("error when reading data:", error)
//            }
//        }
    }
    
    
    public func stop() {
        CFSocketInvalidate(cfSocket)
        cfSocket = nil
    }
}



extension SscceServer: SscceSocketDelegate {
    public func readData(from socket: CFSocket) {
        let inputStream = socket.createStreamPair().inputStream
        defer {
            inputStream.close()
        }
        inputStream.open()
        
        do {
            self.requestHandler(.some(try inputStream.readToData()))
        }
        catch let error {
            self.requestHandler(.none(error))
        }
    }
    
    
    public func acceptNewConnection(from socket: CFSocket, childSocketHandle: CFSocketNativeHandle) {
        readData(from: socket)
    }
    
    
    public func dataCallback(socket: CFSocket, readData: Data) {
        self.requestHandler(.some(readData))
    }
    
    
    public func socketDidConnect(socket: CFSocket, errorCode: Int32?) {
        if let errorCode = errorCode,
            errorCode != 0 {
            print("Socket failed to connect:", String(errno: errorCode))
            self.requestHandler(.none(FailedToConnect(errno: errorCode)))
        }
        else {
            print("Socket connected")
        }
    }
    
    
    public func writeCallback(socket: CFSocket) {
        if let response = self.responseHandler() {
            let outputStream = socket.createStreamPair().outputStream
            defer {
                outputStream.close()
            }
            outputStream.open()
            
            do {
                try outputStream.write(data: response)
            }
            catch let error {
                assertionFailure("Failed to write to output stream: \(error)")
            }
        }
    }
}



// MARK: - Shared utilities



// MARK: Delegate

public protocol SscceSocketDelegate: AnyObject {
    /// Handles when a CFSocket is triggered with a `CFSocketCallBackType.readCallBack`.
    /// It's time to read data from the socket.
    ///
    /// - Parameter socket: The socket from which to read data
    func readData(from socket: CFSocket)
    
    
    
    /// Handles when a CFSocket is triggered with a `CFSocketCallBackType.acceptCallBack`.
    /// A new connection has been accepted on the given socket.
    ///
    /// - Parameters:
    ///   - socket:            The socket on which the connection was accepted
    ///   - childSocketHandle: The OS-level handle for the child socket
    func acceptNewConnection(from socket: CFSocket, childSocketHandle: CFSocketNativeHandle)
    
    
    
    /// Handles when a CFSocket is triggered with a `CFSocketCallBackType.dataCallBack`
    func dataCallback(socket: CFSocket, readData: Data)
    
    
    
    /// Handles when a CFSocket is triggered with a `CFSocketCallBackType.connectCallBack`
    func socketDidConnect(socket: CFSocket, errorCode: Int32?)
    
    
    
    /// Handles when a CFSocket is triggered with a `CFSocketCallBackType.writeCallBack`
    func writeCallback(socket: CFSocket)
}



private extension SscceSocketDelegate {

    func wrapped() -> UnsafeMutableRawPointer {
        return Unmanaged.passRetained(SscceSocketDelegateWrapper(wrapping: self)).toOpaque()
    }
    
    
    func wrappedInContext() -> CFSocketContext {
        var context = CFSocketContext()
        context.version = 0
        context.info = self.wrapped()
        return context
    }
}



private class SscceSocketDelegateWrapper {
    let unwrapped: SscceSocketDelegate
    
    init(wrapping unwrapped: SscceSocketDelegate) {
        self.unwrapped = unwrapped
    }
    
    
    static func unwrapping(_ unsafelyWrapped: UnsafeMutableRawPointer) -> SscceSocketDelegate {
        return Unmanaged<SscceSocketDelegateWrapper>.fromOpaque(unsafelyWrapped).takeUnretainedValue().unwrapped
    }
}



// MARK: Functions

private func basicCallout(socket: CFSocket?,
                          callBackType: CFSocketCallBackType,
                          address: CFData?,
                          callBackTypeMetaData: UnsafeRawPointer?,
                          info: UnsafeMutableRawPointer?) -> Void {
    
    // Behavior inferred from Developer
    // https://developer.apple.com/documentation/corefoundation/cfsocketcallback
    
    guard
        let info = info,
        let socket = socket
        else {
            return assertionFailure("Socket may have gone out of scope before response")
    }
    
    let delegate = SscceSocketDelegateWrapper.unwrapping(info)
    
    
    if callBackType == .readCallBack {
        print("Delegate will read from socket:", socket)
        return delegate.readData(from: socket)
    }
    else if callBackType == .acceptCallBack {
        guard let socketHandle = callBackTypeMetaData?.load(as: CFSocketNativeHandle.self) else {
            return assertionFailure("Raw data could not be converted into a CFSocketNativeHandle")
        }
        
        print("Delegate will accept new connection from socket:", socket)
        delegate.acceptNewConnection(from: socket, childSocketHandle: socketHandle)
    }
    else if callBackType == .connectCallBack {
        guard let statusCode = callBackTypeMetaData?.load(as: Int32.self) else {
            print("Socket connected successfully (no status code)")
            delegate.socketDidConnect(socket: socket, errorCode: nil)
            return
        }
        
        switch statusCode {
        case 0:
            print("Socket connected successfully (status code is 0)")
            delegate.socketDidConnect(socket: socket, errorCode: nil)
            
        default:
            print("Socket could not connect! Error code:", statusCode, "; strerror says:", String(errno: statusCode))
            delegate.socketDidConnect(socket: socket, errorCode: statusCode)
        }
    }
    else if callBackType == .dataCallBack {
        guard let rawPointer = callBackTypeMetaData else {
            return assertionFailure("Data callback had no metadata")
        }
        
        let data = Unmanaged<CFData>.fromOpaque(rawPointer).takeUnretainedValue() as Data
        
        print("Delegate will be given data:", data, "; from socket:", socket)
        delegate.dataCallback(socket: socket, readData: data)
    }
    else if callBackType == .writeCallBack {
        print("Delegate will write to socket:", socket)
        delegate.writeCallback(socket: socket)
    }
    else {
        return assertionFailure("Could not handle socket callback type: \(callBackType)")
    }
}



// MARK: Structures

struct FailedToCreateSocket : Error {
    let errno: errno_t
}



struct SocketAlreadyActive: Error {}



struct FailedToConnect: Error {
    let errno: errno_t
}



struct FailedToBind: Error {
    let errno: errno_t
}



struct FailedToWriteToOutputStream: Error {
    let totalNumberOfBytesWritten: Int
}



struct FailedToReadFromInputStream: Error {
    let totalNumberOfBytesRead: Int
    let dataSoFar: Data?
    
    init(totalNumberOfBytesRead: Int) {
        self.totalNumberOfBytesRead = totalNumberOfBytesRead
        self.dataSoFar = nil
    }
    
    init(dataSoFar: Data) {
        self.totalNumberOfBytesRead = dataSoFar.count
        self.dataSoFar = dataSoFar
    }
}



// MARK: Extensions & Sugar

extension CFSocket {
    
    public static func create(allocator: CFAllocator? = kCFAllocatorDefault,
                              protocolFamily: Int32,
                              socketType: Int32,
                              protocol: Int32,
                              callBackTypes: CFSocketCallBackType,
                              callout: @escaping CFSocketCallBack,
                              context: inout CFSocketContext) -> CFSocket? {
        return CFSocketCreate(allocator,
                              protocolFamily,
                              socketType,
                              `protocol`,
                              callBackTypes.rawValue,
                              callout,
                              &context)
    }


    func createStreamPair(using allocator: CFAllocator? = kCFAllocatorDefault,
                          readStreamProperties: [CFStreamPropertyKey : CFTypeRef] = [:],
                          writeStreamProperties: [CFStreamPropertyKey : CFTypeRef] = [:]
        ) -> (inputStream: InputStream, outputStream: OutputStream) {
        
        var cfReadStream: Unmanaged<CFReadStream>?
        var cfWriteStream: Unmanaged<CFWriteStream>?
        
        CFSocket.createPair(using: allocator,
                   withSocket: CFSocketGetNative(self),
                   readStream: &cfReadStream,
                   writeStream: &cfWriteStream)
        
        let inputStream = cfReadStream!.takeRetainedValue()
        let outputStream = cfWriteStream!.takeRetainedValue()
        
        readStreamProperties.forEach { keyValuePair in
            let (key, value) = keyValuePair
            CFReadStreamSetProperty(inputStream, key, value)
        }
        
        writeStreamProperties.forEach { keyValuePair in
            let (key, value) = keyValuePair
            CFWriteStreamSetProperty(outputStream, key, value)
        }
        
        return (inputStream as InputStream, outputStream as OutputStream)
    }
    
    
    public static func createPair(using allocator: CFAllocator? = kCFAllocatorDefault,
                                  withSocket socketNativeHandle: CFSocketNativeHandle,
                                  readStream: UnsafeMutablePointer<Unmanaged<CFReadStream>?>?,
                                  writeStream: UnsafeMutablePointer<Unmanaged<CFWriteStream>?>?) {
        return CFStreamCreatePairWithSocket(allocator,
                                            socketNativeHandle,
                                            readStream,
                                            writeStream)
    }
    
    
    public func connect(to address: CFData, timeout: TimeInterval = 10) throws {
        errno = 0
        let connectResult = CFSocketConnectToAddress(self, address, timeout)
        let errnoAfter = errno
        
        switch connectResult {
        case .error, .timeout:
            throw FailedToConnect(errno: errnoAfter)
            
        case .success:
            if errnoAfter == 0 {
                print("Successfully connected")
            }
            else {
                throw FailedToConnect(errno: errnoAfter)
            }
        }
    }
    
    
    public func bind(to address: CFData) throws {
        
        print((address as Data).withUnsafeBytes({ (unsafeBytes: UnsafePointer<sockaddr>) -> sockaddr in
            return unsafeBytes.pointee
        }))
        
        errno = 0
        let addressSetResult = CFSocketSetAddress(self, address)
        let errnoAfter = errno
        
        switch addressSetResult {
        case .error, .timeout:
            throw FailedToBind(errno: errnoAfter)
            
        case .success:
            if errnoAfter == 0 {
                print("Successfully bound")
            }
            else {
                throw FailedToBind(errno: errnoAfter)
            }
        }
    }
}



extension CFSocketError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .error:
            return "error"
            
        case .success:
            return "success"
            
        case .timeout:
            return "timeout"
        }
    }
}



extension String {
    init(errno: errno_t) {
        self.init(cString: strerror(errno))
    }
}



extension OutputStream {
    @discardableResult
    public func write(data: Data) throws -> Int {
        var numberOfBytesRemaining = data.count
        
        while numberOfBytesRemaining > 0, self.hasSpaceAvailable {
            let numberOfBytesWritten = data.withUnsafeBytes { bytes in
                self.write(bytes, maxLength: numberOfBytesRemaining)
            }
            
            switch numberOfBytesWritten {
            case ..<0: // Error; failure; unknown number of bytes written
                throw self.streamError
                    ?? FailedToWriteToOutputStream(totalNumberOfBytesWritten: data.count - Swift.max(0, numberOfBytesRemaining))
                
            case 0: // Done; successful; no bytes written
                break
                
            default:
                numberOfBytesRemaining -= numberOfBytesWritten
                continue
            }
        }
        
        let totalNumberOfBytesWritten = data.count - Swift.max(0, numberOfBytesRemaining)
        
        return totalNumberOfBytesWritten
    }
}



extension InputStream {
    
    public func readToData(bufferSize: Int = 1024) throws -> Data {
        var data = Data()
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        while self.hasBytesAvailable {
            let numberOfBytesRead = self.read(buffer, maxLength: bufferSize)
            
            switch numberOfBytesRead {
            case 0: // Done; successful; no more bytes left
                break
                
            case -1: // Error; failure; no more bytes left
                throw self.streamError ?? FailedToReadFromInputStream(totalNumberOfBytesRead: data.count)
                
            default:
                data.append(buffer, count: numberOfBytesRead)
            }
        }
        buffer.deallocate(capacity: bufferSize)
        
        return data
    }
}



extension Stream.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notOpen: return "Not Open"
        case .opening: return "Opening"
        case .open:    return "Open"
        case .reading: return "Reading"
        case .writing: return "Writing"
        case .atEnd:   return "At End"
        case .closed:  return "Closed"
        case .error:   return "Error"
        }
    }
}



public extension Data {
    public init<T>(rawBytesIn value: inout T, deallocator: Data.Deallocator = .unmap) {
        self.init(bytesNoCopy: &value, count: MemoryLayout.size(ofValue: value), deallocator: deallocator)
    }
}
