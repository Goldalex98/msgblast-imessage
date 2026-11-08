import Contacts
import Foundation
import msgblastCore

// iMessage companion (fork-only). Names for uplinked participants, from the Mac's Contacts. It never asks for
// access itself; the app's onboarding already does.

protocol ContactSource {
    func authorized() -> Bool
    func allHandles() -> [(name: String, handles: [String])]
}

extension CNContactStore: ContactSource {
    func authorized() -> Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }

    func allHandles() -> [(name: String, handles: [String])] {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactOrganizationNameKey as CNKeyDescriptor,
                                       CNContactPhoneNumbersKey as CNKeyDescriptor,
                                       CNContactEmailAddressesKey as CNKeyDescriptor]
        var result: [(name: String, handles: [String])] = []
        try? enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let full = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let name = full.isEmpty ? contact.organizationName : full
            guard !name.isEmpty else { return }
            let handles = contact.phoneNumbers.map(\.value.stringValue) + contact.emailAddresses.map { $0.value as String }
            if !handles.isEmpty { result.append((name, handles)) }
        }
        return result
    }
}

final class ContactNameResolver: CompanionNameResolving, @unchecked Sendable {
    private let store: ContactSource
    private let refreshEvery: TimeInterval
    private let lock = NSLock()
    private var index: [String: String] = [:]
    private var loadedAt: Date?

    init(store: ContactSource = CNContactStore(), refreshEvery: TimeInterval = 600) {
        self.store = store
        self.refreshEvery = refreshEvery
    }

    var isAuthorized: Bool { store.authorized() }

    func names(for handles: [String]) async -> [String: String] {
        guard store.authorized() else {
            lock.withLock { index = [:]; loadedAt = nil }
            return [:]
        }
        let table = currentIndex()
        var result: [String: String] = [:]
        for handle in handles {
            if let key = Self.key(handle), let name = table[key] { result[handle] = name }
        }
        return result
    }

    private func currentIndex() -> [String: String] {
        if let cached = lock.withLock({ loadedAt.map { Date().timeIntervalSince($0) < refreshEvery } == true ? index : nil }) {
            return cached
        }
        var fresh: [String: String] = [:]
        for person in store.allHandles() {
            for handle in person.handles {
                if let key = Self.key(handle), fresh[key] == nil { fresh[key] = person.name }
            }
        }
        lock.withLock { index = fresh; loadedAt = Date() }
        return fresh
    }

    /// Emails lowercased; phone numbers by their last 10 digits.
    static func key(_ handle: String) -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return trimmed.lowercased() }
        let digits = trimmed.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(10))
    }
}
