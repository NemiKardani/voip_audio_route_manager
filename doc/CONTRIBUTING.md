# Contributing to VoIP Audio Route Manager

Thank you for your interest in contributing to the VoIP Audio Route Manager project! This guide explains how the repository is structured, how to set up your local development environment, write tests, make changes, and submit pull requests.

---

## 1. Repository Structure

This repository is structured as a **federated Flutter plugin**, meaning different platform implementations are split into separate packages. This keeps the codebase modular and allows platform-specific development without cluttering other platforms.

* **[voip_audio_route_manager](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager)**: The core package that developers import in their Flutter apps. It also contains the **[example app](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager/example)**.
* **[voip_audio_route_manager_platform_interface](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager_platform_interface)**: Defines the common API and contract that all platform implementations must follow.
* **[voip_audio_route_manager_android](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager_android)**: Android-specific implementation using Kotlin and AudioManager.
* **[voip_audio_route_manager_ios](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager_ios)**: iOS-specific implementation using Swift and AVAudioSession.
* **[voip_audio_route_manager_macos](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager_macos)**: macOS-specific implementation using Swift.
* **[voip_audio_route_manager_web](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/voip_audio_route_manager_web)**: Web-specific implementation using dart:html/web and W3C Audio Output Devices API.

---

## 2. Local Environment Setup

This project uses **FVM (Flutter Version Manager)** to ensure consistency across developers and CI/CD.

1. **Install FVM** if you haven't already:
   ```bash
   dart pub global activate fvm
   ```
2. **Install the project Flutter version** by running this in the repository root:
   ```bash
   fvm install
   ```
3. **Get dependencies** across all federated packages:
   ```bash
   for dir in voip_audio_route_manager_platform_interface voip_audio_route_manager_android voip_audio_route_manager_ios voip_audio_route_manager_macos voip_audio_route_manager_web voip_audio_route_manager; do
     echo "=== Fetching dependencies in $dir ==="
     (cd $dir && fvm flutter pub get)
   done
   ```

---

## 3. Making Changes

### Guidelines
* **Do not duplicate implementation logic**: If a feature is common to all platforms, implement it in the core or platform interface packages.
* **Follow Dart & Flutter formatting guidelines**: Always format your code before committing.
* **Keep docstrings up-to-date**: Preserve or add documentation comments (`///`) for public APIs.

---

## 4. Running Sanity Checks Locally

Our CI/CD pipeline runs sanity checks on every Pull Request. To avoid build failures, verify your changes locally before pushing them:

1. **Verify Code Formatting**:
   ```bash
   fvm flutter format --set-exit-if-changed .
   ```
2. **Run Static Analysis (Lints)**:
   ```bash
   # Run in each modified package folder
   fvm flutter analyze
   ```
3. **Run Unit and Widget Tests**:
   ```bash
   # Run in modified package folder (e.g. core package)
   fvm flutter test
   ```

---

## 5. Submitting a Pull Request (PR)

1. Create a new branch for your feature or fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Make your changes and commit them:
   ```bash
   git commit -m "feat: your descriptive commit message"
   ```
3. Push your branch to GitHub:
   ```bash
   git push origin feature/your-feature-name
   ```
4. Create a Pull Request against the `main` branch.
5. Ensure all **Sanity Checks** in the GitHub Actions matrix pass successfully. Once reviewed and green, your PR can be merged.

---

## 6. Releasing and Publishing

When releasing new versions to pub.dev:

1. Update the version inside `pubspec.yaml` for each package you want to publish.
2. Add a new release entry in the root **[changelog.yaml](file:///Users/nemi_s_mac/Documents/Development/Flutter_Devlopment/packages/audio_session_manager/voip_audio_route_manager/changelog.yaml)** file:
   ```yaml
   releases:
     - package_name: voip_audio_route_manager
       version: 1.2.0
       commit_id: "abcdefg"
       changes:
         - "Description of changes made in this version."
   ```
3. Update `CHANGELOG.md` in the corresponding package folders.
4. Merge these changes to `main`.
5. Trigger the release by pushing a tag (e.g. `v1.2.0`) or using the manual workflow dispatch under the Actions tab.
6. The pub.dev author will verify the dry-run, approve the deployment through GitHub Environments, and the pipeline will automatically publish the packages using OIDC.
