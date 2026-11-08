import XCTest
@testable import msgblastCore

final class ContactNameResolverTests: XCTestCase {
    private struct FakeContacts: ContactSource {
        var isAllowed = true
        var people: [(name: String, handles: [String])] = [
            ("Test Person", ["+1 (555) 010-0001"]),
            ("Example Org", ["Test@Example.invalid"]),
        ]
        func authorized() -> Bool { isAllowed }
        func allHandles() -> [(name: String, handles: [String])] { people }
    }

    func test_matchesPhoneAcrossFormats() async {
        let names = await ContactNameResolver(store: FakeContacts()).names(for: ["+15550100001", "5550100001"])
        XCTAssertEqual(names, ["+15550100001": "Test Person", "5550100001": "Test Person"])
    }

    func test_matchesEmailCaseInsensitive() async {
        let names = await ContactNameResolver(store: FakeContacts()).names(for: ["test@example.INVALID"])
        XCTAssertEqual(names, ["test@example.INVALID": "Example Org"])
    }

    func test_unknownHandleHasNoName() async {
        let names = await ContactNameResolver(store: FakeContacts()).names(for: ["+15550100099", "other@example.invalid"])
        XCTAssertEqual(names, [:])
    }

    func test_differentCountryCodesDontMatch() async {
        let contacts = FakeContacts(people: [("Abroad Person", ["+44 555 010 0001"]), ("Local Person", ["555-010-0002"])])
        let names = await ContactNameResolver(store: contacts).names(for: ["+15550100001", "+445550100001", "+15550100002"])
        XCTAssertEqual(names, ["+445550100001": "Abroad Person", "+15550100002": "Local Person"],
                       "explicit, different country codes never match; a contact without one matches by national number")
    }

    func test_deniedReturnsNoNames() async {
        let resolver = ContactNameResolver(store: FakeContacts(isAllowed: false))
        XCTAssertFalse(resolver.isAuthorized)
        let names = await resolver.names(for: ["+15550100001"])
        XCTAssertEqual(names, [:])
    }
}
