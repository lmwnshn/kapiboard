# Implementation Plan

## Prototype Constraints

- No paid Apple Developer account is required for the local prototype.
- WeatherKit is deferred. Weather uses Open-Meteo for now.
- FinanceKit is deferred.
- Stocks use Yahoo's unofficial chart endpoint through `YahooChartMarketProvider`.
- Gmail should use Gmail API OAuth, not web scraping.
- WidgetKit source is included, but creating/running the extension requires a full Xcode app project.

## MVP Order

1. Build the SwiftUI macOS dashboard with empty states when live data is unavailable.
2. Poll Open-Meteo and Yahoo every 60 seconds from the main app.
3. Cache `DashboardSnapshot` to Application Support, later App Group.
4. Add EventKit calendar/reminder providers.
5. Add Gmail OAuth and unread summary provider.
6. Move the app into a full Xcode project and attach the WidgetKit extension target.
7. Add launch-at-login.

## Current Google Path

Google Calendar and Gmail use OAuth with read-only scopes. Tokens are stored in Keychain.

For local development, configure the OAuth desktop client with `~/.kapiboard/google.json`, `Config/google.local.json`, or `KAPIBOARD_GOOGLE_CONFIG`:

```json
{
  "googleClientID": "YOUR_CLIENT_ID.apps.googleusercontent.com",
  "googleClientSecret": "YOUR_CLIENT_SECRET"
}
```

`~/.kapiboard/google.json` should be mode `600`; `Config/google.local.json` is ignored by Git. Do not commit real OAuth credentials.

## Distribution Notes

For eventual user distribution:

- Replace Yahoo unofficial data if reliability or terms become a problem.
- Use a proper App Group identifier for app/widget snapshot sharing.
- Configure Google OAuth consent. Gmail read scopes may require Google verification for broad distribution.
- Use notarized direct distribution first unless App Store constraints are required.

## Local Build

The Swift package portion can be built with:

```bash
swift build
```

Full macOS app bundling and WidgetKit require Xcode selected with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```
