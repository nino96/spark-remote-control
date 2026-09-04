# Bubblewrap AppArmor policy

`bwrap-userns-restrict` comes from Ubuntu Noble's signed
`apparmor-profiles` package:

- Version: `4.0.1really4.0.1-0ubuntu0.24.04.7`
- Packaged path: `/usr/share/apparmor/extra-profiles/bwrap-userns-restrict`
- Original SHA-256: `11d39094f044f0cda0febb3ad517b830301da6b2ce929664af09ee9e4dd264f9`
- Retrieved: 2026-09-04

The repository copy has one provenance comment prepended. The two-profile
design lets `/usr/bin/bwrap` initialize namespaces and then stacks sandbox
children with `unpriv_bwrap`, which strips capabilities. This is safer than an
`unconfined` bwrap profile or globally disabling Ubuntu's userns restriction.

