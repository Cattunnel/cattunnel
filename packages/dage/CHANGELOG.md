## 1.0.9-cattunnel.1 (local patch, not published)

- Fix `AgeHeader._calculateMac` deriving the MAC key with a 1-byte salt
  instead of the spec-required empty salt.
- Fix `UnknownStanza.serialize()` using padded base64 and adding a spurious
  trailing newline, so re-serializing a header containing an unknown/grease
  stanza (age's anti-fingerprinting decoy) produced different bytes than the
  original, breaking MAC verification.
- Both bugs made every file encrypted by a spec-compliant age implementation
  (rage/pyrage, the reference Go/Rust age, etc.) fail to decrypt with
  "Incorrect mac", even though the file key itself was recovered correctly.

## 1.0.9

- Testing release flow mostly.

## 1.0.8

- Fixes related to the testkit vectors.

## 1.0.7

- Improve code quality.

## 1.0.6

- Enable longer keys with Bech32.

## 1.0.5

- Use List<int> for parameters, Uint8List for return types.

## 1.0.4

- Make plugin list modifiable.

## 1.0.3

- Relax dependency requirements.

## 1.0.2

- Read password from tty when stdin is not terminal.
- Refactor plugin structure for extensibility.

## 1.0.1

- Export passphrase provider.

## 1.0.0

- Everything from spec implemented.

## 0.0.2

- Added examples and improved documentation.

## 0.0.1

- Initial version.
