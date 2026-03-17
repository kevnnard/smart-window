import Foundation

let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
let fn = unsafeBitCast(sym, to: GetIsPlayingFn.self)

let group = DispatchGroup()
group.enter()
fn(DispatchQueue.main) { isPlaying in
    print("Is Playing: \(isPlaying)")
    group.leave()
}
group.wait()
