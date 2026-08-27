# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: on the repository, open the
**Security** tab and click **Report a vulnerability**. Include your macOS
version, the Chiaro version, and steps to reproduce.

This is a personal project rather than a staffed one, so treat response times
accordingly: the maintainer will acknowledge a report within a week.

## Scope

A report about Chiaro can reasonably be about:

- **The MCP server** (ADR 0008). It binds to `127.0.0.1` only, listening on
  port 24242 with a fallback to an ephemeral port if that's taken. It checks
  the Origin header by exact host match against `127.0.0.1`, `::1`, and
  `localhost`, and caps request bodies at 16 MB. It has no authentication, by
  design: the threat model is that any process already running on the machine
  is trusted, the same as a local Unix socket. A report that the server
  accepts requests from another machine, or from a spoofed Origin, is in
  scope; a report that it has no login is not, since that's the design.
- **File handling.** Sidecar JSON decoding, and RAW decoding through Apple's
  own frameworks (`CIRAWFilter` and friends).
- **Distribution.** The DMG is ad-hoc signed, not notarized. Chiaro asks
  GitHub for the latest release tag and points you to the release page; it
  never downloads or replaces itself (ADR 0014), so there is no update
  channel to spoof. Get new versions from the GitHub release page rather
  than a mirror.

## Out of scope

Reports that require a compromised local machine to work. If an attacker
already has code execution on the machine Chiaro runs on, Chiaro's local
trust model doesn't hold, and that's true of most local-first software.
