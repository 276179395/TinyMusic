import AVFoundation

/// C 回调必须建立在非 MainActor 上下文里：CoreMedia 会在自己的队列上调用
/// prepare/process，如果闭包被推断成 @MainActor，会触发 dispatch_assert_queue 崩溃。
enum EQTap {
    static func callbacks(for processor: EQProcessor) -> MTAudioProcessingTapCallbacks {
        MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(processor).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { tap, _, format in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let processor = Unmanaged<EQProcessor>.fromOpaque(storage).takeUnretainedValue()
                processor.prepare(format: format.pointee)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                var timeRange = CMTimeRange.zero
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut
                )
                guard status == noErr else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let processor = Unmanaged<EQProcessor>.fromOpaque(storage).takeUnretainedValue()
                processor.process(frames: Int(numberFramesOut.pointee), bufferList: bufferListInOut)
            }
        )
    }
}
