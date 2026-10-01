# Contributing to HydroCap

HydroCap is source-available under [PolyForm Noncommercial 1.0.0](LICENSE), not an OSI-approved Open Source license. Third-party dependencies retain their own licenses.

## Before submitting

- Submit only code/artwork you are entitled to contribute. Do not copy vendor-app source, vendor schemas, unlicensed community implementations, or Apple SF Symbols into Android assets or app branding.
- Keep changes focused and test the actual production logic. Include reproducible tests for protocol, calendar, permission, or concurrency changes.
- Do not include personal device identity, Health data, real intake logs, private paths/endpoints, secrets, or signing credentials. Label generated test data explicitly synthetic.
- Preserve the safe command allowlist. Requests for reset/DFU/UV/calibration or unrestricted protocol writes are outside the product's scope.
- Avoid guaranteed volume-accuracy, medical, background-timing, notification-delivery, or store-approval claims.

## Build and test

Follow [Android](android/README.md) and [iOS](ios/README.md) setup instructions. Cross-platform fixtures are documented [here](android/app/src/test/resources/parity/README.md). Native/device tests are separate from pure-logic tests.

## Contributions and commercial licensing

A contribution does not automatically transfer copyright ownership or grant the maintainers a separate commercial relicensing right. Agree any commercial/contributor rights arrangement with the maintainers explicitly before acceptance. The maintainer can grant separate commercial permission only for material over which the relevant licensing authority exists.

For ordinary noncommercial contribution proposals and commercial-license inquiries, contact the project maintainers through the repository. Do not post confidential commercial terms or sensitive debug logs in public issues.
