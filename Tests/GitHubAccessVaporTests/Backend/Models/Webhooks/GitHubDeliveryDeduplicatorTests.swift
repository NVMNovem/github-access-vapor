//
//  GitHubDeliveryDeduplicatorTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Testing

@testable import GitHubAccessVapor

@Suite("GitHubDeliveryDeduplicator")
struct GitHubDeliveryDeduplicatorTests {

    @Test("accepts an identifier once")
    func acceptsOnce() async {
        let deduplicator = GitHubDeliveryDeduplicator()

        #expect(await deduplicator.register("a") == true)
        #expect(await deduplicator.register("a") == false)
        #expect(await deduplicator.register("a") == false)
    }

    @Test("keeps identifiers apart")
    func keepsIdentifiersApart() async {
        let deduplicator = GitHubDeliveryDeduplicator()

        #expect(await deduplicator.register("a") == true)
        #expect(await deduplicator.register("b") == true)
        #expect(await deduplicator.register("a") == false)
    }

    @Test("forgets the oldest identifier once it is full")
    func evictsOldest() async {
        let deduplicator = GitHubDeliveryDeduplicator(capacity: 2)

        #expect(await deduplicator.register("a") == true)
        #expect(await deduplicator.register("b") == true)
        #expect(await deduplicator.register("c") == true)

        // "a" was evicted to make room for "c"; "b" and "c" are still remembered.
        #expect(await deduplicator.register("b") == false)
        #expect(await deduplicator.register("c") == false)
        #expect(await deduplicator.register("a") == true)
    }

    @Test("stays within its capacity")
    func staysWithinCapacity() async {
        let deduplicator = GitHubDeliveryDeduplicator(capacity: 8)

        for index in 0..<1_000 {
            _ = await deduplicator.register("delivery-\(index)")
        }

        #expect(await deduplicator.count == 8)
    }

    @Test("admits an identifier exactly once under concurrency")
    func admitsOnceUnderConcurrency() async {
        let deduplicator = GitHubDeliveryDeduplicator()

        let admissions = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<64 {
                group.addTask { await deduplicator.register("same-delivery") }
            }

            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }

        #expect(admissions == 1)
    }
}
