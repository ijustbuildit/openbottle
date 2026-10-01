# Release checklist

Source publication and store/binary distribution are separate approvals. A private development repository must not be made public merely because its latest files have been cleaned: prior commits can still contain personal information, device captures, and signing identity.

## Source publication

- Export an allowlisted, sanitized source snapshot without the private repository's `.git` directory or ignored files.
- Create a new publication baseline with approved non-personal author/committer attribution. Do not rewrite or force-push the private development history as a substitute for this step.
- Review every exported text/binary file, generated projects, examples, encoded fixtures, artwork provenance, licensing, notices, and new Git metadata.
- Exclude raw personal captures, worker briefs, local reports, build outputs, machine paths, signing keys/accounts, and credentials.
- Include `LICENSE`, third-party license texts/notices, build instructions, compatibility limits, privacy information, and calibration caveats.
- Rebuild and test the exact exported sources. Distinguish JVM/Swift tests, native UI tests, real-device behavior, and signed release builds.
- Obtain the owner's explicit final public GO before creating/pushing a public remote or changing any repository's visibility.

## Android binaries / stores

- Inspect the actual release dependency graph and packaged notices, not only a direct-dependency list.
- Choose release signing and publisher identity explicitly. Never distribute the development signing key or claim a debug APK is a store release.
- Verify permissions, backup/data extraction behavior, Health Connect declarations, notification behavior, install/update paths, and the store's currently applicable target/API requirements.
- Verify that update signing and application IDs preserve existing data. Do not uninstall or clear data to work around failures.
- Recheck compatibility on the actual supported hardware and label unvalidated profiles/configurations.

## iOS / App Store

- Use Xcode with the actual iPhoneOS SDK, local signing team and entitlements; CLI Catalyst typechecking is not sufficient for a signed release.
- Exercise real Bluetooth/Health permission sheets, state restoration, first import, charts, background behavior, and notifications on an iPhone.
- Validate compiled assets, original icon, privacy/Health disclosures, provisioning, archive, and App Store metadata.
- Confirm third-party rights and review requirements without treating technical interoperability as guaranteed store approval.

## Data and safety

Do not upload debug logs, screenshots of real intake/Health records, device identifiers, or signing/account details as release evidence. Use synthetic screenshots when public screenshots are needed, clearly distinguish them from hardware testing, and never insert synthetic data into a user's real Health store.
