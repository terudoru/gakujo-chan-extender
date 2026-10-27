import Foundation
import Security

@main
struct DarwinSecureStorageTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() throws {
        var calls = 0
        let denied = FlutterSecureStorage(
            keychainDelete: { _ in calls += 1; return errSecSuccess },
            accessControlFactory: { _, _ in nil }
        )
        var params = KeychainQueryParameters(key: "synthetic", service: "synthetic.test", usesDataProtectionKeychain: false)
        params.accessControlFlags = "userPresence"
        do {
            _ = try denied.baseQuery(from: params)
            fatalError("Requested access control must not be discarded")
        } catch let error as OSSecError {
            expect(error.status == errSecParam, "Access control failure must be reported")
        }
        expect(denied.write(params: params, value: "synthetic").status == errSecParam,
               "Write must fail when requested protection cannot be created")
        expect(calls == 0, "A failed protected write must not delete any item")

        params.accessControlFlags = "unknownFlag"
        do {
            _ = try denied.baseQuery(from: params)
            fatalError("Unknown access control flags must be rejected")
        } catch let error as OSSecError {
            expect(error.status == errSecParam, "Unknown access control flag must be reported")
        }

        params.accessControlFlags = nil
        params.isSynchronizable = true
        let plainQuery = try denied.baseQuery(from: params)
        expect(plainQuery[kSecAttrSynchronizable] as? Bool == true, "Synchronizable default must be preserved")
        params.shouldReturnData = true
        let updateQuery = try denied.mutationQuery(from: params)
        expect(updateQuery[kSecReturnData] == nil && updateQuery[kSecReturnPersistentRef] == nil,
               "Mutation queries must not include return-result keys")

        func runDelete(_ statuses: [OSStatus], enclave: Bool) -> (OSStatus, Int) {
            var index = 0
            let storage = FlutterSecureStorage(keychainDelete: { _ in
                guard index < statuses.count else { fatalError("Unexpected keychain deletion") }
                defer { index += 1 }
                return statuses[index]
            })
            var deleteParams = KeychainQueryParameters(service: "synthetic.test", usesDataProtectionKeychain: false)
            deleteParams.useSecureEnclave = enclave
            return (storage.deleteAll(params: deleteParams).status, index)
        }

        let partial = runDelete([errSecSuccess, errSecAuthFailed], enclave: true)
        expect(partial.0 == errSecAuthFailed && partial.1 == 2,
               "Partial deletion must fail and retain the enclave key")
        let reverse = runDelete([errSecAuthFailed, errSecSuccess], enclave: true)
        expect(reverse.0 == errSecAuthFailed && reverse.1 == 2,
               "Both variants must be attempted even if the first fails")
        let keyFailure = runDelete([errSecItemNotFound, errSecSuccess, errSecAuthFailed], enclave: true)
        expect(keyFailure.0 == errSecAuthFailed && keyFailure.1 == 3,
               "Enclave key deletion failures must be reported")
        let complete = runDelete([errSecItemNotFound, errSecSuccess, errSecItemNotFound], enclave: true)
        expect(complete.0 == errSecSuccess && complete.1 == 3, "Missing items count as deleted")
        var narrowedCalls = 0
        let narrowed = FlutterSecureStorage(keychainDelete: { _ in narrowedCalls += 1; return errSecSuccess })
        var narrowedParams = KeychainQueryParameters(service: "synthetic.test", usesDataProtectionKeychain: false)
        narrowedParams.useSecureEnclave = true
        narrowedParams.itemLabel = "synthetic label"
        expect(narrowed.deleteAll(params: narrowedParams).status == errSecSuccess && narrowedCalls == 2,
               "Narrowed deletion must retain the shared enclave key")
        print("Darwin secure storage regression tests passed")
    }
}
