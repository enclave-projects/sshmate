<!-- Copyright 2026 SSH Mate contributors. SPDX-License-Identifier: GPL-3.0-only -->
# Termius investigation

Investigated on 20 October 2026. This is an independent implementation study, not a claim of complete compatibility. No proprietary source, fonts, icons, account data, or services are included in SSH Mate.

## Target and method

The installed Termius 10.2.1 Electron package was inspected at `<local Termius installation>/resources/app.asar`.

- Artifact SHA-256: `dc2f4bf69399bf0093f50143702e9760073d1df53b5bf795a6d6849741d0f08c`.
- Initial package inventory evidence: `ev_f6717f60cc6ef30c9d7eaa9f8268b883b9db47cfdf0365a3dc2f8862d31a57bf`.
- Focused REA static analysis: `ev_70f9c2f9bd6b97a402797a6994b2ca57264f68be719f1291478654d36f4bc8a7`.
- Summary projection: `ev_f5cfd5ab00f574774199cdf144eb1f7af594d06f6286632856a80d3421efbf4d`.
- Focused facts projection: `ev_190b4183e546213c7c88e9fcedea0a6aff38e23ecfa76ecb5e12741d35b871fb`.

REA parsed eight selected JavaScript files as inert text: 154,798 bytes, eight successful parses, zero parse failures. It retained inventory identity for 8,167 relevant files, leaving 8,159 outside source analysis. Application and semantic graph coverage are partial. Evidence IDs identify retained REA records; this document is a compact ledger rather than an export containing proprietary payloads.

REA reported inconsistent integrity metadata for `node_modules/@termius/node-pty/win-x64/winpty-agent.exe`. Analysis used `record-and-continue`; the observed helper bytes are untrusted. No target code was executed. This does not establish tampering or explain the mismatch.

## Findings ledger

All module names below are relative to `ui-process/assets/`. Findings describe packaged UI labels and static syntax; availability and successful operation were not observed.

| Source in focused REA analysis | Observation | What remains unknown |
| --- | --- | --- |
| `HostsScreenSidebar-221ca8fe.js` | Host/group detail editors; IP or hostname, IP version, parent group, tags, SSH and Telnet forms | Inheritance rules, complete validation, authentication and network execution |
| `HostsFiltersHeader-cbccb9ea.js` | Member invitation controls and pending invite UI | Server behavior, permissions enforcement |
| `PortForwardingRulePresenter-4942c31a.js` | Port forwarding presentation with a dynamic rule label | Supported tunnel modes and lifecycle behavior |
| `SftpSettings-0af044b2.js` | File type associations for applications selected through Open with | Transfers, remote editing and conflict handling |
| `LogsSettings-1cc25f55.js` | Per-vault logging controls; delete logs and disable confirmation | Log storage format, encryption, redaction and retention |
| `Vaults-d8ada1cd.js` | Named vaults, member access, view/edit permissions, duplicate name checks | Cryptographic protocol, account recovery and server trust |
| `FreeFeatures-f3d50a10.js` | AI snippets, text to command, terminal multiplayer, encrypted cloud backup/sync promotion | Actual entitlement and service operation |
| `ProFeatures-e310eebe.js` | Subscription and feature presentation | Full entitlement matrix |

An additional read-only ASAR parser examined string literals in `reconnectSaga-9aed66e2.js` (member SHA-256 `57eb93dffb8bac55b8a640ae588053c3d44903e7895fe87e2c2ea7c116dccfc9`). Labels mention identities, SSH keys/certificates, FIDO2 devices, Serial, Mosh, broadcast mode, workspace templates, and SSH/CSV import. This supplemental string inspection is not a REA semantic trace and does not prove implementation or reachability.

## Design interpretation

Dark-theme selectors, host sidebar/edit screens, and named workspace controls support a desktop workspace interpretation. SSH Mate uses an original dark navigation rail, searchable host cards, reusable credentials and tabbed terminals. Exact visual equivalence is unverified: no screenshot comparison or interactive Termius session was captured.

## Unresolved investigation

A second bounded REA pass selected seven core main/preload/background/UI/service bundles (15,148,986 bytes). It parsed three, skipped four after worker heap exhaustion, reported zero parse failures, and retained partial relationships. Parent evidence: `ev_e8b16e8a5e4a48288b31f1255c2811b17a48d31bb3dbd48ea1f2247209ddba46`; compact metadata is in `research/core-analysis-summary.json`. The main-process, preload, background main, and reconnect bundles exceeded the selected 2 GiB per-worker heap. This expands inspected scope without resolving those feature behaviors. The 8,160 unselected files in this pass include dependencies and assets; they were inventoried, not semantically analyzed.

Full terminal behavior, nested groups, proxy/jump hosts, reconnect semantics, SFTP conflict resolution, serial devices, Mosh, hardware credentials, team synchronization and cryptographic key management require focused follow-up and controlled runtime evidence. No production SSH servers, user credentials, saved Termius vaults, account records, or network traffic were inspected. See [ROADMAP.md](ROADMAP.md) for explicit implementation gaps.

