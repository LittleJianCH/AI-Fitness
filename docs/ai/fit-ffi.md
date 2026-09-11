# C++ and the FIT FFI Boundary

**Read when:** editing the Garmin SDK adapter, Haskell FFI, C ABI, or FIT decoder behavior.

The C++ component is a narrow Garmin SDK adapter, not another application backend. Prefer RAII, standard containers, clear ownership, and ordinary code over template-heavy abstractions. Isolate the third-party SDK; pin its source and build inputs and avoid unrelated modifications to vendor code. [cpp-guidelines] [garmin-fit]

Expose a small, documented C ABI. Do not expose C++ classes, exceptions, `std::string`, or STL container layouts through it. Define byte lengths, error statuses, allocation/free ownership, lifetime, encoding, and behavior for empty or invalid input. Memory allocated by the adapter must be released through its matching API, or copied under an explicitly defined ownership contract.

Catch C++ exceptions before crossing the ABI and map them to bounded explicit errors. Use Haskell-side resource management so decode failures and cancellation do not leak buffers. SDK decoding stays in `IO` unless a deliberately reviewed pure wrapper can genuinely uphold purity and memory-safety obligations. Do not use `unsafePerformIO` merely to make a type signature look functional.

Treat long-running SDK decoding as potentially blocking work. Select `safe`/`unsafe` FFI annotations from runtime requirements and measured behavior; `safe` is not a memory-safety proof or a timeout. Arbitrary CPU-heavy native work cannot be made reliably cancellable merely by adding `interruptible`. Limit input size/resource usage and document cancellation limitations. [ghc-ffi]

Validate malformed, truncated, missing, invalid-sentinel, and unsupported data explicitly. Do not convert absent sensor readings to zero or invent unavailable fields. Use SDK-supported encode/decode paths where applicable and document the export subset rather than claiming lossless round-tripping of all FIT extensions.

Suggested checks: one clang-format configuration, compiler warnings for project-owned code, relevant clang-tidy rules, ASan/UBSan in a dedicated adapter test build where supported, and malformed-input/regression tests. A standalone adapter test harness is allowed; it is not a replacement parser subprocess in the product architecture.

[cpp-guidelines]: references.md#cpp-guidelines
[garmin-fit]: references.md#garmin-fit
[ghc-ffi]: references.md#ghc-ffi
