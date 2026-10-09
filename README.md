# GitLabMobile

A small native SwiftUI iOS app for the GitLab actions you reach for on a phone.

## Features

- **Merge requests**: open MRs where you're a reviewer, assignee, or author. Open one to
  approve or revoke approval, and merge (squash / delete-branch options). If the pipeline is
  still running it offers "merge when pipeline succeeds". If GitLab reports a blocker
  (unresolved threads, needs rebase, conflicts, and so on), the button is disabled and shows the reason.
- **Pipelines**: browse your projects (pin favourites with a swipe), filter pipelines by status,
  and open one to see jobs by stage. You can retry the pipeline's failed jobs, retry or cancel an
  individual job, and play manual jobs one at a time or advance the next manual stage in one tap.
  A running pipeline auto-refreshes every 5s.
- Self-hosted GitLab supported (enter your server URL).

## Build

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open GitLabMobile.xcodeproj
```

Set your signing team in Xcode, then run on a device or simulator (iOS 17+).

## Auth

Create a personal access token (Preferences → Access tokens) with the **`api`** scope; approving,
merging and retrying all need write access. The token is kept in the iOS Keychain.

## Layout

- `API/`: `GitLabClient` (REST v4), `Models`
- `App/`: app entry, `Session` (auth state + Keychain)
- `Views/`: SwiftUI screens

## Not yet supported

Pagination beyond the first 50/30 items, child (downstream) pipelines, job logs, push notifications, OAuth.
