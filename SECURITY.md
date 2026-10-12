# Security policy

The latest published release is the supported version. Fixes are delivered through new releases; update before reporting a problem.

Use GitHub's private **Report a vulnerability** feature in the repository's Security tab. Do not put exploit details, private media or credentials in a public issue. If that feature is unavailable, ask the maintainer for a private reporting channel without posting sensitive details.

Vela is a local media application. Lua extensions are trusted programs with filesystem and network access; they are not a sandbox. Use extensions from sources you trust. Execution deadlines, bounded Lua memory and managed command cancellation reduce accidental hangs but do not make a hostile script safe. Capture permissions are requested through macOS when a real source is opened.

Release signing status and known limitations are documented with each release. No disclosure response time is guaranteed by this community project.
