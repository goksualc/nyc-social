import XCTest
import UIKit
@testable import Along

@MainActor
final class AvatarFlowTests: XCTestCase {
    private func makeStore(_ backend: MockAlongBackend) async throws -> AppStore {
        try await AppStore.bootstrap(backend: backend)
    }

    private func sampleJPEG() -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400))
        return r.jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        }
    }

    // MARK: Whole flow

    func testPickUploadUpdateShowAndPersist() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        XCTAssertNil(store.me.avatarPath)

        let ok = await store.setAvatar(jpeg: sampleJPEG())
        XCTAssertTrue(ok)
        let path = try XCTUnwrap(store.me.avatarPath, "the new photo shows in the app immediately")
        XCTAssertTrue(path.hasPrefix("me/avatar-"), "stored under the user's own folder: \(path)")
        let stored = await backend.storedAvatarPaths
        XCTAssertEqual(stored, [path])

        // "Restart / log out and back in": a fresh load from the backend still has the photo.
        let reloaded = try await backend.loadMyProfile()
        XCTAssertEqual(reloaded.user.avatarPath, path)
        let restarted = try await makeStore(backend)
        XCTAssertEqual(restarted.me.avatarPath, path)
    }

    func testReplacingAPhotoDeletesTheOldFile() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        _ = await store.setAvatar(jpeg: sampleJPEG())
        let first = try XCTUnwrap(store.me.avatarPath)
        try await Task.sleep(for: .milliseconds(5))          // filenames carry the millisecond, so a later upload gets a new name
        _ = await store.setAvatar(jpeg: sampleJPEG())
        let second = try XCTUnwrap(store.me.avatarPath)
        XCTAssertNotEqual(first, second)
        let remaining = await backend.storedAvatarPaths
        XCTAssertEqual(remaining, [second], "only the current photo is kept")
    }

    // MARK: The bugs this fixes

    func testSavingTheProfileFormNeverBringsBackAnOldPhoto() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        let staleDraft = store.me                           // the edit form copies the profile when it opens (no photo yet)
        _ = await store.setAvatar(jpeg: sampleJPEG())
        let path = try XCTUnwrap(store.me.avatarPath)

        var edited = staleDraft
        edited.bio = "New bio"
        await store.updateProfile(edited)                   // …then the person taps Save

        XCTAssertEqual(store.me.bio, "New bio")
        XCTAssertEqual(store.me.avatarPath, path, "saving other fields must not overwrite the photo")
        let persisted = try await backend.loadMyProfile()
        XCTAssertEqual(persisted.user.avatarPath, path)
    }

    func testFailedProfileWriteRemovesTheUploadedFileAndKeepsTheOldPhoto() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        await backend.setFailAvatarProfileUpdate(true)
        let ok = await store.setAvatar(jpeg: sampleJPEG())
        XCTAssertFalse(ok)
        XCTAssertNil(store.me.avatarPath)
        let leftovers = await backend.storedAvatarPaths
        XCTAssertTrue(leftovers.isEmpty, "no orphaned file after a failed update")
    }

    func testFailedUploadChangesNothing() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        await backend.setFailAvatarUpload(true)
        let ok = await store.setAvatar(jpeg: sampleJPEG())
        XCTAssertFalse(ok)
        XCTAssertNil(store.me.avatarPath)
        XCTAssertFalse(store.isUpdatingAvatar, "the spinner always stops")
    }

    func testRemovingThePhotoPersists() async throws {
        let backend = MockAlongBackend(avatarsEnabled: true)
        let store = try await makeStore(backend)
        _ = await store.setAvatar(jpeg: sampleJPEG())
        await store.removeAvatar()
        XCTAssertNil(store.me.avatarPath)
        let reloaded = try await backend.loadMyProfile()
        XCTAssertNil(reloaded.user.avatarPath)
        let files = await backend.storedAvatarPaths
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: Compression and paths

    func testPhotosAreCompressedToASmallSquare() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024))
            .jpegData(withCompressionQuality: 1) { ctx in
                for i in 0..<60 {                           // some detail so the file isn't trivially tiny
                    UIColor(hue: CGFloat(i) / 60, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    ctx.fill(CGRect(x: i * 67, y: (i * 41) % 3000, width: 300, height: 300))
                }
            }
        XCTAssertGreaterThan(big.count, 300_000)
        let out = try XCTUnwrap(AvatarImage.jpeg(from: big))
        XCTAssertLessThan(out.count, AvatarImage.targetBytes + 50_000)
        XCTAssertLessThan(out.count, 2_000_000, "well under the bucket's 2 MB limit")
        let image = try XCTUnwrap(UIImage(data: out))
        XCTAssertEqual(image.size.width * image.scale, 512, accuracy: 1)
        XCTAssertEqual(image.size.height * image.scale, 512, accuracy: 1)
        XCTAssertNil(AvatarImage.jpeg(from: Data("not an image".utf8)))
    }

    func testStoragePathMatchesTheBucketPolicy() {
        let uid = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        let path = AvatarStoragePath.make(userID: uid, now: Date(timeIntervalSince1970: 1_800_000_000.123))
        XCTAssertEqual(path, "abcdef12-3456-7890-abcd-ef1234567890/avatar-1800000000123.jpg")
        // the exact pattern from migration 5's insert policy
        let regex = try! NSRegularExpression(pattern: "^[0-9a-f-]{36}/avatar(-[0-9]+)?\\.(jpg|jpeg|png|webp)$")
        XCTAssertNotNil(regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)))
        XCTAssertNotEqual(path, AvatarStoragePath.make(userID: uid, now: Date(timeIntervalSince1970: 1_800_000_000.124)), "unique per upload")
    }

    func testPhotoWriteTouchesOnlyAvatarUrl() throws {
        let set = try JSONSerialization.jsonObject(with: SupabaseCoding.makeEncoder().encode(AvatarUpdate(avatarUrl: "u/avatar-1.jpg"))) as! [String: Any]
        XCTAssertEqual(Set(set.keys), ["avatar_url"])
        let cleared = try JSONSerialization.jsonObject(with: SupabaseCoding.makeEncoder().encode(AvatarUpdate(avatarUrl: nil))) as! [String: Any]
        XCTAssertTrue(cleared["avatar_url"] is NSNull, "explicit null clears the photo")
        let profile = ProfileUpdate(displayName: "A", bio: "", hobbies: [], instagramUsername: nil, xUsername: nil, occupation: nil, university: nil,
                                    languages: [], favoriteNeighborhoods: [], preferredPace: nil, preferredDuration: nil,
                                    discussionTopics: [], conversationCustom: [], visibility: nil)
        let json = try JSONSerialization.jsonObject(with: SupabaseCoding.makeEncoder().encode(profile)) as! [String: Any]
        XCTAssertNil(json["avatar_url"], "the profile form never sends the photo")
    }
}
