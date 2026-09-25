# Vulnerability scan summary

Tool: Trivy 0.74.0 (vuln scanner) - SBOM: Syft 1.51.0, SPDX JSON format
Image scanned: amsou/msc-de1-flask-app:1.0.0

| Severity | v0 - python:3.12-slim (Debian 13) | Final - python:3.12-alpine (Alpine 3.24) |
|----------|-----------------------------------|------------------------------------------|
| CRITICAL | 0                                 | 0                                        |
| HIGH     | 44                                | 0                                        |
| MEDIUM   | 53                                | 0                                        |
| LOW      | 57                                | 1                                        |
| UNKNOWN  | 2                                 | 0                                        |
| Packages | 104                               | 47                                       |
| Size     | 187 MB                            | 84 MB                                    |

## Analysis of v0
- 0 findings in Python dependencies (Flask, Werkzeug, gunicorn...).
- All 44 HIGH were in Debian OS packages (util-linux, mount, login, ncurses, systemd libs, perl-base),
  status "affected" / "fix_deferred": no fixed version available, none used by the application.

## Changes made after the scan
1. Base image switched from python:3.12-slim to python:3.12-alpine (official image, far fewer OS packages).
2. pip and ensurepip removed from the runtime image (not needed at runtime).
3. Runtime hardening kept: non-root UID 10001, read-only root filesystem, all capabilities dropped,
   no-new-privileges.

## Remaining findings
- 0 HIGH, 0 CRITICAL. 1 LOW finding remains (see vulnerability-scan.txt), accepted as low risk.

Files: vulnerability-scan.txt (final), vulnerability-scan-high-critical.txt (final),
vulnerability-scan-v0-slim*.txt (before), sbom.spdx.json (final image SBOM).
