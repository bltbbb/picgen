import Foundation
import Photos
import UIKit

enum SaveError: LocalizedError {
    case denied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "没有相册权限，去 设置 → 隐私与安全性 → 照片 里打开"
        case .failed(let msg):
            return "保存失败：\(msg)"
        }
    }
}

enum PhotoSaver {
    static func save(_ image: UIImage, done: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { done(.failure(SaveError.denied)) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, error in
                DispatchQueue.main.async {
                    if ok {
                        done(.success(()))
                    } else {
                        done(.failure(SaveError.failed(error?.localizedDescription ?? "未知错误")))
                    }
                }
            }
        }
    }
}
