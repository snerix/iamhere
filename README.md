# Here

> Which country are you on the internet right now?

A tiny macOS menu bar app that answers that question, always. Flip a VPN, hop WiFi, toggle Clash — **Here** tells you at a glance where your traffic actually leaves from.

<p align="center">
  <em>🇺🇸 CA&nbsp;&nbsp;·&nbsp;&nbsp;38.175.104.131&nbsp;&nbsp;·&nbsp;&nbsp;San Jose, United States</em>
</p>

## The pill

A rounded pill in your menu bar: flag + region code. Border goes **red** the moment the latency probe says the network's actually broken. When the egress can't be verified (airplane mode, IP service unreachable), the pill flips to a **random flag + `OO`** — an honest "I don't know" instead of a stale lie.

Click for the popover:

- **Location** — big copyable IP, mini Maps preview, ASN details, and IPPure quality signals.
- **History** — recent egress changes as a flag chain with "time ago" labels.
- **Latency** — rolling 30-probe bar, color-coded green / yellow / orange / red.
- **Throughput** — on-demand download speed test (Cachefly / Cloudflare / custom URL).

## Smart enough to keep up

- Catches **every** meaningful network change — WiFi hops, VPN up/down, Clash "system proxy" flips. The widget rechecks on a configurable loop (default: 5s awake, 30s while the display is asleep), so a node switch lands in your menu bar quickly.
- **One shot per change.** No retry storms. Fails fast, respects your sanity.
- Flag follows the **geographic country**, not the ASN country. A VPN registered in HK but serving a Taiwan node shows 🇹🇼, not 🇭🇰.
- **Update checks are disabled by default.** The updater code is kept in the tree, but the settings UI no longer exposes update checks.

## Recent changes

- Switched the IP information provider to IPPure so the app can show IP quality and purity signals.
- Added automatic English, Simplified Chinese, and Japanese localization based on the macOS system language.
- Changed the IP refresh cadence from hard-coded intervals to user-configurable awake/asleep intervals.
- Disabled the visible update-check entry points.

## Install

Grab the latest `.dmg` from [**Releases**](https://github.com/snerix/iamhere/releases) → drag **Here** into **Applications** → first launch: right-click → **Open** (the build is unsigned).

- **macOS 15 Sequoia** or later
- **Apple Silicon + Intel** — universal binary, any Mac that supports Sequoia

## Build from source

```sh
git clone https://github.com/snerix/iamhere.git
cd iamhere
open Here.xcodeproj       # Cmd-R to run, Cmd-U to test
```

Or CLI:

```sh
xcodebuild -project Here.xcodeproj -scheme Here build
xcodebuild -project Here.xcodeproj -scheme Here test
```

## Credits

- IP, location, and quality signals from [**IPPure**](https://ippure.com/) via `https://my.ippure.com/v1/info` — free, no auth, one JSON call. Thank you. (Earlier versions used ip.guide, then ipwho.is.)
- Flag art from [**flagcdn.com**](https://flagcdn.com/) — rectangular PNGs, public-domain.

## License

[MIT](LICENSE)
