# UniverZAP

UniverZAP is a downstream fork of [Chatwoot](https://github.com/chatwoot/chatwoot) maintained by Kennedy Rodrigues.

## Attribution

This project is built on top of the open-source Chatwoot platform.

- Upstream project: https://github.com/chatwoot/chatwoot
- Original copyright: Copyright (c) 2017-2024 Chatwoot Inc.
- The core platform is distributed under the MIT Expat license — see [LICENSE](LICENSE).

We retain the original `LICENSE` file unchanged and acknowledge Chatwoot Inc. as the original copyright holder of the upstream codebase. Modifications, additions and the UniverZAP product layer (branding, integrations, custom features) are © 2026 Kennedy Rodrigues and contributors.

## Enterprise overlay

The upstream Chatwoot repository ships an `enterprise/` directory governed by the Chatwoot Enterprise License (see `enterprise/LICENSE`). UniverZAP **does not enable or distribute** any feature gated by that license in production builds.

The default UniverZAP configuration ships with `DISABLE_ENTERPRISE=true`, which:

- Skips loading any code under `enterprise/` at boot
- Keeps the enterprise overlay dormant for parity reference only
- Allows lawful inspection and modification for development / testing as expressly permitted by the upstream Enterprise License

Equivalent functionality (advanced agent assignment, audit logs, IA agents, SLA, etc.) is being re-implemented from scratch in `app/` under the MIT-compatible UniverZAP core. As that work lands, the `enterprise/` directory will be removed entirely.

## Trademarks

"Chatwoot" is a trademark of Chatwoot Inc. UniverZAP is not affiliated with, endorsed by, or sponsored by Chatwoot Inc.
