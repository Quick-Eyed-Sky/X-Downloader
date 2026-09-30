# X Downloader for macOS

A small SwiftUI application that downloads media from an X/Twitter account using [gallery-dl](https://github.com/mikf/gallery-dl) and the cookies from a signed-in Chrome session.

## Features

- Configurable media limit: **8,000 files by default**.
- **Images only** mode to skip videos.
- File names based on post text.
- Optional removal of exact duplicates using file size and SHA-256 hashes.
- A progress bar driven by gallery-dl's completed-download events.
- Saved preferences and an activity log.

Progress measures downloaded files against the requested limit, not a known account total. It stays below 100% during processing and reaches 100% when the job finishes. If fewer media files are available than requested, it may jump to 100% at completion. It pauses while X applies a rate limit. Duplicate removal can reduce the final file count. The limit applies to each run, not to all files already in the destination folder.

## Requirements

- **macOS 13 Ventura or later**.
- Apple Command Line Tools: `xcode-select --install`.
- [Homebrew](https://brew.sh) and gallery-dl: `brew install gallery-dl`.
- Google Chrome with an active X/Twitter session in the profile selected by gallery-dl.

The app looks for gallery-dl in `/opt/homebrew/bin` and `/usr/local/bin`. gallery-dl is an external dependency and is not bundled. It and its dependencies retain their own licenses.

## Build

Double-click **build.command** in the downloaded project folder. If the script is not executable after downloading from GitHub, open Terminal in that folder and run:

```sh
bash build.command
```

The result is **dist/X Downloader.app**. Open it or copy it into Applications. The script builds for the current Mac's architecture (Apple Silicon or Intel), targeting macOS 13 or later; it does not produce a universal binary. This version was built and launched on Apple Silicon; Intel has not been tested.

The app uses a local ad hoc signature and is not notarized by Apple. Building on your own Mac is recommended. The script preserves the previous build and replaces the app only after successful compilation and verification.

## Usage and Chrome authentication

1. Sign in to **x.com in Chrome** and confirm that you can access the target account.
2. Open X Downloader and enter an account name, with or without `@`.
3. Choose a destination, a file limit, and the options you want.
4. Click **Download**.

The app explicitly invokes `gallery-dl --cookies-from-browser chrome`. It does not ask for your X password or deliberately export a cookies file. gallery-dl reads Chrome cookies locally to authenticate requests to X. macOS may ask for Keychain access to decrypt those cookies.

If the activity log reports **AuthRequired / authenticated cookies needed**:

- Check that you are signed in to X in Chrome and using the intended Chrome profile. This version has no profile picker; gallery-dl selects its default profile.
- Update gallery-dl: `brew upgrade gallery-dl`.
- Check the log for cookie access or decryption errors. Specifying Chrome does not fix an expired or inaccessible session.

X restrictions and upstream changes can prevent downloads. Validation covered compilation, opening the window, and local file-processing checks. A real authenticated download has not been tested.

## Crossed-out application icon

An interrupted build could leave an `.app` folder without an executable, which Finder displayed with a crossed-out icon. Version **3.1.1** fixes a conflict between the `State` type and the `State` macro in some SwiftUI SDKs, explicitly sets the macOS deployment target, and builds in a temporary folder to avoid leaving an incomplete app.

Nonzero gallery-dl exit codes are reported as failures. Partial files remain in the destination's `_raw` subfolder, which also contains local configuration and metadata. Do not publish that folder.

## Privacy and repository contents

The repository contains only source code, the build script, documentation, Git exclusions, and the license. No X account is preselected. Never commit cookies, Chrome profiles, downloaded media, private metadata, or activity logs. `.gitignore` excludes build outputs, common cookie files, and generated data; review files before publishing them.

Use the app for content you can access and are authorized to download. This project is independent of X and Google.

## License

Application code is licensed under the [MIT License](LICENSE).
