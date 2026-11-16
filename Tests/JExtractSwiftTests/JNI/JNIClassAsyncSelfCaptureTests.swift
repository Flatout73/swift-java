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

/// An async thunk converts `self` inside its task, so the task does not capture the converted pointer.
@Suite
struct JNIAsyncSelfCaptureTests {

  @Test("Import: class async method converts self inside the task (Swift)")
  func classAsyncMethod_swift() throws {
    try assertOutput(
      input: """
        public class MyClass {
          public func compute() async -> Int64 { 42 }
        }
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_MyClass__00024compute__JLjava_util_concurrent_CompletableFuture_2")
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        assert(selfPointer != 0, "selfPointer memory address was null")
        let selfPointerBits$ = Int(Int64(fromJNI: selfPointer, in: environment))
        let selfPointer$ = UnsafeMutablePointer<MyClass>(bitPattern: selfPointerBits$)
        ...
        let swiftResult$ = await selfPointer$.pointee.compute()
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }

  @Test("Import: protocol box async method loads the existential inside the task (Swift)")
  func protocolBoxAsyncMethod_swift() throws {
    try assertOutput(
      input: """
        public protocol Worker {
          func work() async -> Int64
        }
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_WorkerBox__00024work__JJLjava_util_concurrent_CompletableFuture_2")
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        guard let selfPointerTypeMetadataPointer$ = UnsafeRawPointer(bitPattern: Int(Int64(fromJNI: selfTypePointer, in: environment))) else {
        ...
        let selfPointerExistential$ = selfPointerRawPointer$.load(as: selfPointerDynamicType$) as! (any Worker)
        ...
        let swiftResult$ = await selfPointerExistential$.work()
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }

  @Test("Import: generic class async method converts self inside the task (Swift)")
  func genericClassAsyncMethod_swift() throws {
    try assertOutput(
      input: """
        public class Box<T> {
          public func compute() async -> Int64 { 42 }
        }
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        extension Box: _SwiftModule_Box_opener {
        ...
        task = Task.immediate {
        var environment = try! JavaVirtualMachine.shared().environment()
        assert(selfPointer != 0, "selfPointer memory address was null")
        let selfPointerBits$ = Int(Int64(fromJNI: selfPointer, in: environment))
        ...
        let swiftResult$ = await selfPointer$.pointee.compute()
        """
      ],
      notExpectedChunks: [
        "UnsafeSendable$"
      ]
    )
  }
}
