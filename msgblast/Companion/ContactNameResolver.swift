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
    private struct Index {
        var emails: [String: String] = [:]
        /// By the last 10 digits. `full` is every digit when the number carried an explicit "+" country code.
        var phones: [String: [(full: String?, name: String)]] = [:]
    }
    private let lock = NSLock()
    private var index = Index()
    private var loadedAt: Date?

    init(store: ContactSource = CNContactStore(), refreshEvery: TimeInterval = 600) {
        self.store = store
        self.refreshEvery = refreshEvery
    }

    var isAuthorized: Bool { store.authorized() }

    func names(for handles: [String]) async -> [String: String] {
        guard store.authorized() else {
            lock.withLock { index = Index(); loadedAt = nil }
            return [:]
        }
        let table = currentIndex()
        var result: [String: String] = [:]
        for handle in handles {
            if let name = Self.lookup(handle, in: table) { result[handle] = name }
        }
        return result
    }

    private func currentIndex() -> Index {
        if let cached = lock.withLock({ loadedAt.map { Date().timeIntervalSince($0) < refreshEvery } == true ? index : nil }) {
            return cached
        }
        var fresh = Index()
        for person in store.allHandles() {
            for handle in person.handles {
                switch Self.key(handle) {
                case .email(let email)?: if fresh.emails[email] == nil { fresh.emails[email] = person.name }
                case .phone(let last10, let full)?: fresh.phones[last10, default: []].append((full, person.name))
                case nil: break
                }
            }
        }
        lock.withLock { index = fresh; loadedAt = Date() }
        return fresh
    }

    private static func lookup(_ handle: String, in table: Index) -> String? {
        switch key(handle) {
        case .email(let email)?:
            return table.emails[email]
        case .phone(let last10, let full)?:
            // Two explicit country codes must agree in full; otherwise the national number decides.
            return table.phones[last10]?.first { candidate in
                guard let full, let other = candidate.full else { return true }
                return full == other
            }?.name
        case nil:
            return nil
        }
    }

    enum Key: Equatable {
        case email(String)
        case phone(last10: String, full: String?)
    }

    /// Emails lowercased; phone numbers by their last 10 digits, plus every digit when written with "+".
    static func key(_ handle: String) -> Key? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return .email(trimmed.lowercased()) }
        let digits = String(trimmed.filter(\.isASCII).filter(\.isNumber))
        guard !digits.isEmpty else { return nil }
        return .phone(last10: String(digits.suffix(10)), full: trimmed.hasPrefix("+") ? digits : nil)
    }
}
