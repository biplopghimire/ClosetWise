import os
import Supabase
import UIKit

/// When a piece checked from a store link is bought, swaps its photo (often the listing's model shot)
/// for one that shows just the item: ClosetWise picks the best item-only photo from the listing's
/// gallery — or, if every photo is on a model, the one where the item shows best, cropped to the item.
/// Runs in the background after Buy; if anything fails the piece keeps the photo it has.
@MainActor
enum ClosetPhotoPicker {
    private static let log = Logger(subsystem: "app.closetwise", category: "photos")

    static func improve(itemID: UUID, store: ClosetStore) async {
        guard let item = store.item(itemID), let options = item.photoOptions, !options.isEmpty else { return }
        let photos = await download(options.compactMap(URL.init(string:)))
        guard !photos.isEmpty else { return clearOptions(itemID, store: store) }

        var chosen = photos[0]
        var crop: CGRect?
        var shows = "unknown"
        if let pick = await ask(photos, item: item) {
            chosen = photos[pick.index]
            shows = pick.shows
            crop = rect(pick.box, in: chosen.size)
        }
        // Crop to the item when it's worn by a model (or the packshot has lots of empty space around it).
        var photo = chosen
        if let crop, shows != "item_only" || crop.width * crop.height < chosen.size.width * chosen.size.height * 0.6 {
            photo = cropped(chosen, to: crop) ?? chosen
        }
        let cut = await GarmentPhoto.cutout(photo) ?? photo
        guard let name = store.savePhoto(cut), var current = store.item(itemID) else { return }
        current.photo = name
        current.photoOptions = nil
        store.updateItem(current)
        log.notice("CLOSETPHOTO picked \(shows, privacy: .public) photo \(photos.firstIndex(of: chosen) ?? -1) of \(photos.count) for \(item.name, privacy: .public)")
    }

    private static func clearOptions(_ id: UUID, store: ClosetStore) {
        guard var item = store.item(id) else { return }
        item.photoOptions = nil
        store.updateItem(item)
    }

    // MARK: Steps

    /// Downloads the listing's photos (in order, skipping failures and small images).
    private static func download(_ urls: [URL]) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, url) in urls.prefix(8).enumerated() {
                group.addTask {
                    var request = URLRequest(url: url, timeoutInterval: 12)
                    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                                     forHTTPHeaderField: "User-Agent")
                    request.setValue("image/avif,image/webp,image/jpeg,image/png,*/*", forHTTPHeaderField: "Accept")
                    guard let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data),
                          image.size.width >= 250, image.size.height >= 250 else { return (i, nil) }
                    return (i, image)
                }
            }
            var found: [(Int, UIImage)] = []
            for await (i, image) in group { if let image { found.append((i, image)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private struct Pick { let index: Int; let shows: String; let box: [Int] }

    private static func ask(_ photos: [UIImage], item: WardrobeItem) async -> Pick? {
        guard let client = SupabaseService.client, await Cloud.shared.ensureSession() != nil else { return nil }
        struct Request: Encodable { let action = "pick_product_photo"; let name: String; let category: String; let images: [String] }
        struct Response: Decodable { let index: Int; let shows: String; let box_2d: [Int] }
        let thumbs = photos.compactMap { $0.resized(maxSide: 512).jpegData(compressionQuality: 0.7)?.base64EncodedString() }
        do {
            let r: Response = try await client.functions.invoke(
                "gemini", options: FunctionInvokeOptions(body: Request(name: item.name, category: item.category.rawValue, images: thumbs)))
            guard photos.indices.contains(r.index) else { return nil }
            return Pick(index: r.index, shows: r.shows, box: r.box_2d)
        } catch {
            log.error("pick_product_photo failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// [ymin, xmin, ymax, xmax] on 0–1000 → a rect in the image, padded a little, or nil if it's nonsense.
    private static func rect(_ box: [Int], in size: CGSize) -> CGRect? {
        guard box.count == 4 else { return nil }
        let (y0, x0, y1, x1) = (CGFloat(box[0]), CGFloat(box[1]), CGFloat(box[2]), CGFloat(box[3]))
        guard y1 > y0, x1 > x0, y1 - y0 > 50, x1 - x0 > 50 else { return nil }
        var r = CGRect(x: x0 / 1000 * size.width, y: y0 / 1000 * size.height,
                       width: (x1 - x0) / 1000 * size.width, height: (y1 - y0) / 1000 * size.height)
        r = r.insetBy(dx: -r.width * 0.06, dy: -r.height * 0.06)
        return r.intersection(CGRect(origin: .zero, size: size))
    }

    private static func cropped(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = image.scale; return f
        }())
        return renderer.image { _ in image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY)) }
    }
}
