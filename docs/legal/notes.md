# Implementation provenance and release caveats

This is a project policy and source register, not legal advice or a legal clearance certificate.

HydroCap is an independently written local interoperability client. Vendor binaries, decompiled source, vendor schema files, screenshots, credentials, and private captures are not distributed as project source. Protocol identifiers and wire fields are documented only where relevant to interoperability; no vendor cloud access is implemented.

## Project rules

1. Write implementations independently. Community repositories and vendor-app observations are evidence for interface facts, not permission to copy source code. Repositories without a license are not reusable code dependencies.
2. Keep hardware identifiers and personal measurements out of examples. Use explicitly generated synthetic protocol fixtures and sanitized scientific calibration observations.
3. Use original branding. BRITA/LARQ names identify compatible hardware only; no affiliation, endorsement, or trademark license is claimed.
4. Keep the enforced safe command scope: clock sync, reminder settings, and quiet hours are the only cap-setting write classes. No firmware update, reset, UV control, or cap-calibration path is provided.
5. Preserve third-party notices and license terms. HydroCap's project license does not replace dependency licenses.
6. Use independently authored bottle artwork for app icons and Android artwork. Apple's SF Symbols are not licensed for app icons/logos or their confusingly similar substitutes. System symbols used within the native iOS UI are a separate platform-use context.

## Relevant sources and qualifications

- [§ 69e UrhG](https://www.gesetze-im-internet.de/urhg/__69e.html) sets conditional limits for decompilation necessary for interoperability. Necessary-information, lawful-use, scope, use, and disclosure restrictions must all be considered; it is not an unconditional right to publish vendor material.
- [§ 69g UrhG](https://www.gesetze-im-internet.de/urhg/__69g.html) addresses conflicting contract terms, subject to the applicable legal framework.
- [§ 3 GeschGehG](https://www.gesetze-im-internet.de/geschgehg/__3.html) addresses observation/study/testing of lawfully possessed or publicly available products; contractual and other applicable conditions matter.
- [§ 23 MarkenG](https://www.gesetze-im-internet.de/markeng/__23.html) provides qualified descriptive/intended-purpose trademark-use rules. Descriptive compatibility wording is not blanket trademark clearance.
- [Apple's SF Symbols guidance](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) and [Xcode/Apple SDK agreement, System-Provided Images](https://www.apple.com/legal/sla/docs/xcode.pdf) prohibit symbols or confusingly similar images in app icons/logos/trademark uses and separately limit system-image platform use.
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) include originality, third-party intellectual-property, Health, privacy, and service-access requirements. Not using a vendor cloud does not guarantee acceptance or make every third-party-authorization question inapplicable.

The tested cap workflow did not require application-level authentication or bonding. That is an observation about the tested configuration, not a universal statement that every firmware/device has no access protection or that all reverse engineering is unrestricted.

## Project license and publication

Original project code and artwork use [PolyForm Noncommercial 1.0.0](../../LICENSE), a source-available noncommercial license. A separate commercial grant requires authority from the relevant rights holders. Third-party dependencies retain their original licenses.

Source publication, App Store submission, Google Play submission, signing, and store privacy disclosures are distinct steps. No vendor authorization or store approval is claimed. Obtain jurisdiction-appropriate legal review where necessary before distribution; decide the publisher identity and store obligations separately from technical readiness.
