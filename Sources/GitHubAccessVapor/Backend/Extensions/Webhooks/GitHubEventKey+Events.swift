//
//  GitHubEventKey+Events.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

extension GitHubEventKey where Event == GitHubReleaseEvent {

    /// The `release` event.
    public static var release: GitHubEventKey<GitHubReleaseEvent> { .init() }
}
