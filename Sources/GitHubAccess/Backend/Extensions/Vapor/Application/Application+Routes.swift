//
//  Application+Routes.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

import Foundation
import Vapor

extension Application {
    
    func configureRoutes(project: String) async throws {
        get("github", "setup") { req async throws -> Response in
            guard let installationID = req.query[String.self, at: "installation_id"] else {
                throw Abort(.badRequest, reason: "Missing installation_id.")
            }
            
            let redirectURL = "\(project.lowercased())://github/setup-complete?installation_id=\(installationID)"
            
            let html =
            """
            <!doctype html>
            <html lang="en">
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <meta http-equiv="refresh" content="0; url=\(redirectURL)">
                <title>\(project) Setup</title>
            
                <style>
                    :root {
                        color-scheme: light dark;
                        --accent: #F03C2E;
                    }
            
                    body {
                        margin: 0;
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                        background: linear-gradient(180deg, #111 0%, #1c1c1c 100%);
                        color: #fff;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        height: 100vh;
                    }
            
                    .container {
                        text-align: center;
                        max-width: 420px;
                        padding: 40px 24px;
                        background: rgba(255, 255, 255, 0.04);
                        border-radius: 16px;
                        backdrop-filter: blur(12px);
                        border: 1px solid rgba(255, 255, 255, 0.08);
                    }
            
                    .logo {
                        width: 64px;
                        height: 64px;
                        margin-bottom: 20px;
                    }
            
                    h1 {
                        font-size: 26px;
                        margin-bottom: 12px;
                    }
            
                    p {
                        color: rgba(255,255,255,0.7);
                        margin-bottom: 24px;
                    }
            
                    .button {
                        display: inline-block;
                        padding: 12px 18px;
                        border-radius: 10px;
                        background: var(--accent);
                        color: white;
                        text-decoration: none;
                        font-weight: 600;
                        transition: transform 0.1s ease, opacity 0.1s ease;
                    }
            
                    .button:hover {
                        transform: translateY(-1px);
                        opacity: 0.9;
                    }
            
                    .footer {
                        margin-top: 20px;
                        font-size: 12px;
                        color: rgba(255,255,255,0.4);
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <!-- Replace src with your hosted SVG path -->
                    <img class="logo" src="/logo.svg" alt="\(project) logo">
            
                    <h1>Connected to GitHub</h1>
                    <p>Your GitHub account is now linked.<br>\(project) should open automatically.</p>
            
                    <a class="button" href="\(redirectURL)">Open \(project)</a>
            
                    <div class="footer">
                        If nothing happens, click the button above.
                    </div>
                </div>
            
                <script>
                    window.location.href = "\(redirectURL)";
                </script>
            </body>
            </html>
            """
            
            let response = Response(status: .ok)
            response.headers.contentType = .html
            response.body = .init(string: html)
            return response
        }
    }
}
