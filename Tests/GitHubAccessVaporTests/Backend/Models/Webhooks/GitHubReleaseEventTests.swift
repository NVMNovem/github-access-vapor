//
//  GitHubReleaseEventTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

@testable import GitHubAccessVapor

@Suite("GitHubReleaseEvent")
struct GitHubReleaseEventTests {

    @Test("decodes the fields a handler needs")
    func decodesReleasePayload() throws {
        let delivery = GitHubWebhookDelivery(
            id: "1",
            event: .release,
            payload: GitHubWebhookFixture.releasePublished
        )

        let event = try delivery.decode(GitHubReleaseEvent.self)

        #expect(event.action == .published)
        #expect(event.release.tagName == "1.4.0")
        #expect(event.release.id == 900)
        #expect(event.release.draft == false)
        #expect(event.release.prerelease == false)
        #expect(event.repository.fullName == "octocat/hello-world")
        #expect(event.repository.defaultBranch == "main")
        #expect(event.repository.isPrivate == true)
        #expect(event.installation?.id == 12345678)
        #expect(event.sender?.login == "octocat")
        #expect(event.release.publishedAt != nil)
    }

    @Test("ignores fields GitHub added after this package shipped")
    func ignoresUnknownFields() throws {
        let payload = Data("""
        {
          "action": "published",
          "brand_new_top_level_field": {"anything": [1, 2, 3]},
          "release": {"tag_name": "2.0.0", "brand_new_release_field": "surprise"},
          "repository": {"full_name": "octocat/hello-world", "brand_new_repo_field": true}
        }
        """.utf8)

        let event = try JSONDecoder().decode(GitHubReleaseEvent.self, from: payload)

        #expect(event.release.tagName == "2.0.0")
        #expect(event.repository.fullName == "octocat/hello-world")
    }

    @Test("keeps an action it does not recognise")
    func keepsUnknownAction() throws {
        let payload = Data("""
        {
          "action": "some_action_that_does_not_exist_yet",
          "release": {"tag_name": "2.0.0"},
          "repository": {"full_name": "octocat/hello-world"}
        }
        """.utf8)

        let event = try JSONDecoder().decode(GitHubReleaseEvent.self, from: payload)

        #expect(event.action.rawValue == "some_action_that_does_not_exist_yet")
        #expect(event.action != .published)
    }

    @Test("defaults the fields a trimmed payload leaves out")
    func defaultsMissingFields() throws {
        let payload = Data("""
        {
          "action": "published",
          "release": {"tag_name": "2.0.0"},
          "repository": {"full_name": "octocat/hello-world"}
        }
        """.utf8)

        let event = try JSONDecoder().decode(GitHubReleaseEvent.self, from: payload)

        #expect(event.release.draft == false)
        #expect(event.release.prerelease == false)
        #expect(event.release.assets.isEmpty)
        #expect(event.release.name == nil)
        #expect(event.repository.isPrivate == false)
        #expect(event.installation == nil)
        #expect(event.sender == nil)
    }

    @Test("tolerates a null published_at")
    func toleratesNullPublishedAt() throws {
        let payload = Data("""
        {
          "action": "created",
          "release": {"tag_name": "2.0.0", "published_at": null, "name": null},
          "repository": {"full_name": "octocat/hello-world"}
        }
        """.utf8)

        let event = try JSONDecoder().decode(GitHubReleaseEvent.self, from: payload)

        #expect(event.release.publishedAt == nil)
        #expect(event.release.name == nil)
    }

    @Test("still refuses a payload that is not a release event")
    func rejectsUnrelatedPayload() {
        let payload = Data(#"{"action":"opened","issue":{"number":1}}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(GitHubReleaseEvent.self, from: payload)
        }
    }

    @Test("names itself after the release event")
    func declaresItsEventName() {
        #expect(GitHubReleaseEvent.eventName == .release)
        #expect(GitHubEventKey<GitHubReleaseEvent>.release.name == .release)
        #expect(GitHubEventName.release.rawValue == "release")
    }
}
