import UIKit

/// Turns a photo or product link into a draft item: background removal on the phone,
/// then ClosetWise (Gemini) reads type, colour, fit and cut. Falls back to reading the
/// colour on the phone when Gemini can't answer. Reports each step to a `GeminiTask`.
@MainActor
enum ItemReader {
    static func photoTask(title: String = "ClosetWise is sizing it up") -> GeminiTask {
        GeminiTask(title: title, steps: [
            "Taking it off the hanger (removing the background)",
            "Reading the label — type, colour and fit",
            "Laying it out for you to check",
        ])
    }

    static func linkTask() -> GeminiTask {
        GeminiTask(title: "ClosetWise is window-shopping", steps: [
            "Peeking at the product page (some stores take a few seconds)",
            "Taking it off the hanger (removing the background)",
            "Sizing it up — type, colour and fit",
            "Laying it out for you to check",
        ])
    }

    static func read(photo image: UIImage, store: ClosetStore, task: GeminiTask) async -> (WardrobeItem, ConfirmRequest.Source) {
        task.step(0)
        let cut = await GarmentPhoto.cutout(image)
        task.step(1)
        var item = AttributeGuesser.guess(ProductDraft())
        var source = ConfirmRequest.Source.photo
        if let gemini = await GarmentPhoto.geminiAttributes(image) {
            item = merge(gemini, into: item)
            source = .gemini
        } else {
            task.step(1, title: "No fitting room free — reading the colour on your phone")
            if let color = DominantColor.of(cut ?? image) {
                item.hex = color.hex
                item.color = color.name
            }
        }
        task.step(2)
        item.photo = store.savePhoto(cut ?? image)
        task.succeed(source == .gemini ? "All measured up — check the details." : "Colour read from your photo — fill in the rest.")
        return (item, source)
    }

    static func read(link: String, store: ClosetStore, task: GeminiTask) async throws -> (WardrobeItem, ConfirmRequest.Source) {
        task.step(0)
        let (page, image) = try await ProductLinkFetcher.read(link)
        let listing = ProductLinkFetcher.draft(from: page)
        let storeName = page.store ?? "the store"

        var cut: UIImage?
        if let image {
            task.step(1)
            cut = await GarmentPhoto.cutout(image) ?? image
        } else {
            task.skip(1)
        }

        task.step(2)
        var item: WardrobeItem
        var source: ConfirmRequest.Source
        if let reading = await GarmentPhoto.geminiProduct(page, image: image) {
            guard reading.isProduct else { throw ProductLinkFetcher.FetchError.notAProduct }
            item = reading.item
            // Exact structured price first; otherwise ClosetWise's reading of the price label (it can tell
            // a sale price from a crossed-out one), then the label's first amount.
            item.price = ProductLinkFetcher.structuredPrice(page) ?? reading.price ?? listing.price
            item.store = storeName
            source = .gemini
        } else {
            // ClosetWise couldn't be reached: go on what the listing says.
            task.step(2, title: "No fitting room free — reading the listing on your phone")
            guard !listing.name.isEmpty else { throw ProductLinkFetcher.FetchError.nothingFound(storeName) }
            item = AttributeGuesser.guess(listing)
            if let cut, let color = DominantColor.of(cut), listing.colorText == nil {
                item.hex = color.hex
                item.color = color.name
            }
            source = .link(storeName)
        }

        task.step(3)
        if let cut { item.photo = store.savePhoto(cut) }
        let price = item.price.map { " · \($0.dollars)" } ?? ""
        task.succeed(source == .gemini ? "Found it at \(storeName)\(price) — check the details." : "Pulled from the listing — check the fit and type.")
        return (item, source)
    }

    private static func merge(_ gemini: WardrobeItem, into item: WardrobeItem) -> WardrobeItem {
        var out = gemini
        out.price = item.price ?? gemini.price
        out.store = item.store
        if item.name != "New item" && !item.name.isEmpty { out.name = item.name }
        return out
    }
}
