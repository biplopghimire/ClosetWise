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
            "Peeking at the product page",
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
        let draft = try await ProductLinkFetcher.fetch(link)
        var item = AttributeGuesser.guess(draft)
        var source = ConfirmRequest.Source.link(draft.store ?? "the store")
        if let image = draft.image {
            task.step(1)
            let cut = await GarmentPhoto.cutout(image) ?? image
            task.step(2)
            if let gemini = await GarmentPhoto.geminiAttributes(image) {
                item = merge(gemini, into: item)
                source = .gemini
            } else {
                task.skip(2)
            }
            item.photo = store.savePhoto(cut)
        } else {
            task.skip(1); task.skip(2)
        }
        task.step(3)
        task.succeed(source == .gemini ? "All measured up — check the details." : "Pulled from the listing — check the fit and type.")
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
