# Bugbook Repo Instructions

This repo is often worked in a dirty tree. Keep changes narrowly scoped and do not bundle unrelated local work into a ticket commit.

## Before You Claim A Change Is Clean

Run these from `/Users/maxforsey/Code/bugbook`:

```bash
swift build
swift test
bash scripts/smoke-cli.sh
```

If you touched the macOS app shell or AppKit integration, also run:

```bash
cd macos && xcodegen generate
xcodebuild -project /Users/maxforsey/Code/bugbook/macos/Bugbook.xcodeproj -scheme BugbookApp -configuration Debug build
```

Do not say "CI passed" unless the commit has been pushed and the GitHub Actions workflow finished successfully.

## Commit Hygiene

- Commit only the files for the accepted ticket or batch.
- Leave unrelated tracked modifications alone unless the user explicitly asks to include them.
- Do not stage local tool folders, generated build output, or workspace-specific metadata.

## Xcode Project — Adding Swift Files

The macOS app uses an Xcode project (`macos/Bugbook.xcodeproj`). When you add a new `.swift` file under `Sources/Bugbook/`, you MUST also add it to `project.pbxproj` (PBXFileReference, PBXBuildFile, the parent PBXGroup, and the Sources build phase). Files on disk but missing from the pbxproj will compile fine via `swift build` but fail in Xcode with "Cannot find type in scope" errors.

## CI Notes

- The source of truth for package validation is SwiftPM (`swift build`, `swift test`).
- The macOS Xcode project is generated from `macos/project.yml`.
- If CI is being changed, prefer explicit SDK detection plus real failures over `|| echo` masking.

## Testing The App Against An Isolated Profile

Never launch a dev build against the real user profile. The app's entire
Application Support profile (Settings/, WorkspaceLayouts/, EditorDrafts/,
AiThreads/, icons/, covers/, …) can be redirected with:

```bash
BUGBOOK_APP_SUPPORT_DIR=/tmp/my-test-profile \
BUGBOOK_PROFILE_WORKSPACE_PATH=/tmp/my-test-workspace \
BUGBOOK_SKIP_KEYCHAIN_SECRETS=1 BUGBOOK_DISABLE_SENTRY=1 \
.build/debug/Bugbook
```

`BUGBOOK_APP_SUPPORT_DIR` overrides the profile root directly (resolved in
`BugbookPaths.profileDirectory`) — do NOT rely on `$HOME`/`CFFIXED_USER_HOME`
redirection alone; a mangled `$HOME` launch once wrote test state into the
real profile. The UI tests (`Tests/BugbookUITests`) set this automatically.

## Bugbook Ticket Notes

When reading an Agent Ticket body, do not use the raw JSON output directly. Extract only the markdown body:

```bash
bugbook get "Agent Tickets" <row_id> --body | jq -r '.body // ""'
```

This avoids writing serialized row JSON back into the ticket body.
