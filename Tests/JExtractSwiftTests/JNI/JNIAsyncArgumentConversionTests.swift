//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

/// The task closures of an async thunk are `sending`. The thunk converts the arguments inside the task,
/// so the task captures only JNI values and global references, never the converted Swift values.
@Suite
struct JNIAsyncArgumentConversionTests {

  @Test("Import: async function converts a value parameter inside the task (Swift)")
  func valueParameter_swift() throws {
    try assertOutput(
      input: """
        public struct Payload {
          public var value: Int64
        }

        public func async(p: Payload) async -> Int64
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_SwiftModule__00024async__JLjava_util_concurrent_CompletableFuture_2")
        public func Java_com_example_swift_SwiftModule__00024async__JLjava_util_concurrent_CompletableFuture_2(environment: UnsafeMutablePointer<JNIEnv?>!, thisClass: jclass, p: jlong, result_future: jobject?) {
        nonisolated(unsafe) let globalFuture = environment.interface.NewGlobalRef(environment, result_future)
        var task: Task<Void, Never>? = nil
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        ...
        assert(p != 0, "p memory address was null")
        let pBits$ = Int(Int64(fromJNI: p, in: environment))
        let p$ = UnsafeMutablePointer<Payload>(bitPattern: pBits$)
        ...
        let swiftResult$ = await SwiftModule.async(p: p$.pointee)
        ...
        task = Task {
        var environment = try! JavaVirtualMachine.shared().environment()
        ...
        assert(p != 0, "p memory address was null")
        ...
        let swiftResult$ = await SwiftModule.async(p: p$.pointee)
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }

  @Test("Import: async function converts an optional class parameter inside the task (Swift)")
  func optionalClassParameter_swift() throws {
    try assertOutput(
      input: """
        public class MyClass { }

        public func async(c: MyClass?) async -> Int64
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_SwiftModule__00024async__JLjava_util_concurrent_CompletableFuture_2")
        public func Java_com_example_swift_SwiftModule__00024async__JLjava_util_concurrent_CompletableFuture_2(environment: UnsafeMutablePointer<JNIEnv?>!, thisClass: jclass, c: jlong, result_future: jobject?) {
        nonisolated(unsafe) let globalFuture = environment.interface.NewGlobalRef(environment, result_future)
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        ...
        let cBits$ = Int(Int64(fromJNI: c, in: environment))
        let c$ = UnsafeMutablePointer<MyClass>(bitPattern: cBits$)
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }

  @Test("Import: async function builds a protocol parameter's existential inside the task (Swift)")
  func protocolParameter_swift() throws {
    try assertOutput(
      input: """
        public protocol Named {
          func name() -> String
        }

        public func async(n: some Named) async -> String
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_SwiftModule__00024async__Ljava_lang_Object_2Ljava_util_concurrent_CompletableFuture_2")
        public func Java_com_example_swift_SwiftModule__00024async__Ljava_lang_Object_2Ljava_util_concurrent_CompletableFuture_2(environment: UnsafeMutablePointer<JNIEnv?>!, thisClass: jclass, n: jobject?, result_future: jobject?) {
        nonisolated(unsafe) let n = environment.interface.NewGlobalRef(environment, n)
        nonisolated(unsafe) let globalFuture = environment.interface.NewGlobalRef(environment, result_future)
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        ...
        let nswiftObject$: (any Named)
        ...
        let swiftResult$ = await SwiftModule.async(n: nswiftObject$)
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }

  @Test("Import: async buffer cleanup uses the current environment before deleting global references", arguments: [false, true], [false, true])
  func bufferCleanup_swift(mutable: Bool, throwing: Bool) throws {
    let bufferType = mutable ? "UnsafeMutableRawBufferPointer" : "UnsafeRawBufferPointer"
    let releaseMode = mutable ? "0" : "jint(JNI_ABORT)"
    let throwsClause = throwing ? " throws" : ""
    let tryClause = throwing ? "try " : ""

    try assertOutput(
      input: "public func receiveBuffer(data: \(bufferType)) async\(throwsClause)",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: ["Task.immediate", "Task"].map { task in
        """
        task = \(task) {
          var environment = try! JavaVirtualMachine.shared().environment()
          defer {
            let deferEnvironment = try! JavaVirtualMachine.shared().environment()
            deferEnvironment.interface.DeleteGlobalRef(deferEnvironment, globalFuture)
            deferEnvironment.interface.DeleteGlobalRef(deferEnvironment, data)
          }
          let data$count = Int(environment.interface.GetArrayLength(environment, data))
          let data$ptr = environment.interface.GetByteArrayElements(environment, data, nil)!
          defer {
            let data$releaseEnvironment = try! JavaVirtualMachine.shared().environment()
            data$releaseEnvironment.interface.ReleaseByteArrayElements(data$releaseEnvironment, data, data$ptr, \(releaseMode))
          }
          let data$rbp = \(bufferType)(start: data$ptr, count: data$count)
          ...
          \(tryClause)await SwiftModule.receiveBuffer(data: data$rbp)
        """
      },
      notExpectedChunks: [
        "environment.interface.ReleaseByteArrayElements(environment,"
      ]
    )
  }

  @Test("Import: async function with primitive parameters converts them inline (Swift)")
  func primitiveParameters_swift() throws {
    try assertOutput(
      input: "public func async(i: Int64, s: String) async -> Int64",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_SwiftModule__00024async__JLjava_lang_String_2Ljava_util_concurrent_CompletableFuture_2")
        ...
        let swiftResult$ = await SwiftModule.async(i: Int64(fromJNI: i, in: environment), s: String(fromJNI: s, in: environment))
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }
}
