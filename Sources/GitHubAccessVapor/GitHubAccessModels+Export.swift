// The release, asset and installation types are defined once, in github-access-api, so a client
// (the iOS app, the web console) and this server decode and encode exactly the same shapes.
// Re-exported so `import GitHubAccessVapor` still brings `GitHubRelease` and `GitHubReleaseAsset`
// into scope as it always has.
@_exported import GitHubAccessModels
