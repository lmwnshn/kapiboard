# DashboardWidget

This directory contains WidgetKit source intended for a real Xcode widget extension target.

Swift Package Manager cannot produce a macOS WidgetKit extension by itself. Once full Xcode is installed, create a macOS app project with a Widget Extension target, add `DashboardCore` as shared source or a local package dependency, and move `DashboardWidget.swift` into the extension target.

The widget reads `dashboard-snapshot.json` through `SnapshotStore`. In production, both the app and extension should use the same App Group identifier.

