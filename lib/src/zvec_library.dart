// Copyright 2025-present the zvec project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:ffi';
import 'dart:io';

import 'zvec_bindings.dart';

/// Singleton accessor for the Zvec native library bindings.
///
/// Handles platform-specific dynamic library loading:
/// - Android: loads `libzvec.so` via [DynamicLibrary.open]
/// - iOS: loads embedded dynamic framework via
///   [DynamicLibrary.open] (`zvec.framework/zvec`)
class ZvecLibrary {
  ZvecLibrary._();

  static ZvecBindings? _bindings;

  /// Returns the singleton [ZvecBindings] instance.
  ///
  /// Throws [UnsupportedError] on unsupported platforms.
  static ZvecBindings get bindings {
    if (_bindings != null) return _bindings!;
    _bindings = ZvecBindings(_openLibrary());
    return _bindings!;
  }

  static DynamicLibrary _openLibrary() {
    // Allow overriding the library path via environment variable.
    // This is needed for host-platform testing where DYLD_LIBRARY_PATH
    // is stripped by macOS System Integrity Protection (SIP).
    final overridePath = Platform.environment['ZVEC_LIBRARY_PATH'];
    if (overridePath != null && overridePath.isNotEmpty) {
      return DynamicLibrary.open(overridePath);
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libzvec.so');
    }
    if (Platform.isIOS) {
      // zvec is packaged as an embedded dynamic framework.
      // CocoaPods places it in the app's Frameworks/ directory.
      return DynamicLibrary.open('zvec.framework/zvec');
    }
    // For testing on host platforms (macOS/Linux/Windows)
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libzvec.dylib');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libzvec.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('zvec.dll');
    }
    throw UnsupportedError(
      'Zvec is not supported on ${Platform.operatingSystem}',
    );
  }
}
