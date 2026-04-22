# KapiBoard AI Notes

This file preserves implementation context that is useful for AI-assisted development and maintenance.

## Current Scope

- SwiftUI dashboard app source.
- Shared snapshot model for app/widget data exchange.
- Open-Meteo weather provider.
- Yahoo unofficial chart endpoint market provider.
- Google Calendar and Gmail API providers via Google OAuth.
- WidgetKit extensions for the main, markets, weather/clocks, links, and arXiv digest widgets.

## Not Yet Wired

- Launch-at-login.

## Build

This repository includes a Swift Package for the app/core source:

```bash
swift build
```

The Xcode project builds the app with embedded WidgetKit extensions:

```bash
./scripts/build_widget_app.sh
```

Install it into the user Applications folder for widget discovery:

```bash
./scripts/install_widget_app.sh
open "$HOME/Applications/KapiBoard.app"
```

The generated app is written to:

```text
DerivedData/Build/Products/Debug/KapiBoard.app
```

After launching it once, open macOS widget editing and look for `KapiBoard`.

## Local App Bundle Scripts

There are legacy local bundle scripts that build and launch an app without the WidgetKit install path:

```bash
./scripts/build_app_bundle.sh
./scripts/run_app.sh
```

The generated app is written to:

```text
dist/KapiBoard.app
```

For widget work, prefer `./scripts/install_widget_app.sh`.

## Google OAuth

KapiBoard requests read-only Google Calendar and Gmail scopes:

- `https://www.googleapis.com/auth/calendar.readonly`
- `https://www.googleapis.com/auth/gmail.readonly`

OAuth tokens are stored in Keychain under:

```text
service: me.wanshenl.KapiBoard.google
account: oauth-token
```

For local development, put Google OAuth desktop client credentials outside the repo:

```bash
mkdir -p ~/.kapiboard
chmod 700 ~/.kapiboard
cp Config/google.example.json ~/.kapiboard/google.json
chmod 600 ~/.kapiboard/google.json
```

Then edit `~/.kapiboard/google.json` with the client ID and client secret. `Config/google.local.json` is also supported and ignored by Git. `KAPIBOARD_GOOGLE_CONFIG` can point to a specific credentials file.

## Prototype Markets

Markets use Yahoo's unofficial chart endpoint through `YahooChartMarketProvider`. This is acceptable for local prototyping, but it should remain behind the provider abstraction because it is unsupported and may break.

## Snapshot And Widgets

The app writes `dashboard-snapshot.json` for widgets to read. `KAPIBOARD_SNAPSHOT_DIR` can override the snapshot directory.

Widget extension bundle IDs:

- `me.wanshenl.KapiBoard.WidgetExtension`
- `me.wanshenl.KapiBoard.DetailWidgetExtension`
- `me.wanshenl.KapiBoard.ArxivWidgetExtension`

App group identifier used by local snapshot paths:

```text
group.me.wanshenl.KapiBoard
```

Current widget set:

- `KapiBoard main`: extra-large main dashboard.
- `KapiBoard lower1`: medium markets view.
- `KapiBoard lower2`: medium weather and clocks view.
- `KapiBoard links`: small configurable URL launcher.
- `KapiBoard arXiv`: large widget showing the latest local cs.DB digest. This is packaged as a dedicated extension bundle because WidgetKit sometimes caches widget families/kinds inside existing extension bundles.

## arXiv Digest

The arXiv widget is file-backed. It does not fetch RSS or call a summarizer from WidgetKit. Populate the digest with:

```bash
scripts/update_arxiv_digest.py
```

To install a daily launch agent that runs the updater at 8:00 AM local time:

```bash
scripts/install_arxiv_digest_launch_agent.sh
```

The script fetches exactly one target day via the arXiv Atom API:

```text
https://export.arxiv.org/api/query
```

The query is constrained to `cat:cs.DB` and one `submittedDate:[YYYYMMDD0000 TO YYYYMMDD2359]` range. The app does not prefetch adjacent days; pressing `PREV` or `NEXT` loads a cached per-day JSON file or fetches only that selected day.

It writes `cs.DB-summary.json` to:

```text
~/.kapiboard/arxiv/cs.DB-summary.json
```

It also mirrors the same file into the widget containers so the sandboxed widgets can read it.

By default, the script summarizes the previous local day, never the current day. It uses the local Codex CLI once per target date when available. It resolves Codex in this order:

1. `--codex-bin`
2. `KAPIBOARD_CODEX_BIN`
3. `codex` on `PATH`
4. `/Applications/Codex.app/Contents/Resources/codex`

If a `status: ready` digest already exists for the target `targetDate`, the script skips summarization and only mirrors the existing file into widget containers. Use `--target-date YYYY-MM-DD` for a specific day, `--force` to regenerate a target date, or `--no-codex` to force the local title-based fallback.

An optional summarizer command can be supplied with `KAPIBOARD_ARXIV_SUMMARIZER` or `--summarizer-command`. This overrides Codex. The command receives raw JSON on stdin and should return JSON with:

```json
{
  "digest": ["one coherent concise paragraph"],
  "paperCategories": [
    {
      "id": "2604.00000v1",
      "title": "Paper title",
      "category": "ML for DB"
    }
  ],
  "items": []
}
```

If Codex is unavailable or fails, the script writes a simple non-LLM digest from the arXiv API titles.
