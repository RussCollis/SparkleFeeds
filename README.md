# Appinfo — App & Sparkle Inspector

Appinfo is a macOS command-line tool for inspecting applications. The installer builds the tool from the included Xcode project and installs it so it can be run from any Terminal window.

## Features

- Builds the `Appinfo` executable using Xcode.
- Installs the command as `/usr/local/bin/appinfo`.
- Creates `appinspect` as a compatibility alias for `appinfo`.
- Supports inspecting an app by passing its path as an argument, according to the tool's command-line interface.

> **Note:** The installer describes Appinfo as an “App & Sparkle Inspector”. The exact inspection fields and options depend on the Appinfo source code and are not defined by `install.sh`.

## Requirements

- macOS.
- Xcode Command Line Tools, including `xcodebuild`.
- The Xcode project and scheme expected by the installer:
  - Project: `Untitled Project.xcodeproj`
  - Scheme: `MyTool`
- Permission to write to `/usr/local/bin` (the installer uses `sudo` if needed).

## Project layout

The installer expects a layout similar to:

```text
project-directory/
├── install.sh
└── Untitled Project.xcodeproj/
```

Build output is written temporarily to `build/` inside the project directory and removed after a successful installation.

## Installation

1. Place `install.sh` alongside `Untitled Project.xcodeproj`.
2. Open Terminal and change to the project directory.
3. Make the installer executable, if required:

   ```bash
   chmod +x install.sh
   ```

4. Run it:

   ```bash
   ./install.sh
   ```

The script builds the Release configuration, copies the resulting `Appinfo` executable to `/usr/local/bin/appinfo`, sets its permissions, and creates the `/usr/local/bin/appinspect` symlink. It may prompt for an administrator password when writing to `/usr/local/bin`.

## Usage

Inspect an application by supplying its path:

```bash
appinfo /Applications/Safari.app
```

You can also use the alias:

```bash
appinspect /Applications/Safari.app
```

To run the tool without an argument:

```bash
appinfo
```

The installer also supports dragging an application from Finder into the Terminal window to insert its path. Drop the app into the command line after typing `appinfo `, then press Return.

## Verify the installation

Check that both commands resolve:

```bash
command -v appinfo
command -v appinspect
```

Expected paths:

```text
/usr/local/bin/appinfo
/usr/local/bin/appinspect
```

Check the installed executable:

```bash
ls -l /usr/local/bin/appinfo /usr/local/bin/appinspect
```

## Uninstallation

Remove the executable and alias:

```bash
sudo rm -f /usr/local/bin/appinfo /usr/local/bin/appinspect
```

This does not remove the Xcode project or source files.

## Troubleshooting

### `xcodebuild` not found

Install Xcode Command Line Tools:

```bash
xcode-select --install
```

If full Xcode is installed but the active developer directory is incorrect, check it with:

```bash
xcode-select -p
```

### Build fails

Confirm that `Untitled Project.xcodeproj` exists beside `install.sh` and that it contains the `MyTool` scheme. Review the Xcode build output; the installer redirects normal build output, so rerun the `xcodebuild` command manually if you need more detail.

### `Could not locate built binary`

The installer searches the build directory for an executable named `Appinfo`. Confirm that the Xcode target produces an executable with that exact name and that the Release build succeeds.

### Permission errors

The installer uses `sudo` to create and update files in `/usr/local/bin`. Make sure your account has administrator privileges.

## Notes

- The installer removes the temporary `build/` directory after installation.
- Re-running the installer replaces the existing `/usr/local/bin/appinfo` binary and refreshes the `appinspect` symlink.
- This README documents behaviour visible in `install.sh`; it does not claim specific inspection output or flags that are not established by the installer.
