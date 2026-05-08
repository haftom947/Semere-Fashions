# Order Tracking Feature Report

## Completed

- Added local `order_status_logs` support in `DatabaseHelper`
  - database version bumped from `35` to `36`
  - created `order_status_logs` table in both `onCreate` and `onUpgrade`
  - added `insertStatusLog(...)`
  - added `getStatusLogsForOrder(...)`
  - added `order_status_logs` to auto-ID and sync-tracked table lists

- Added sync support for remote Firestore collection
  - mapped local table `order_status_logs` to Firestore collection `statusLogs`

- Wired status logging into order status changes
  - `order_details_screen.dart` now records a status log whenever `_updateStatus(...)` runs
  - log includes `orderId`, `status`, `changedBy`, `changedAt`
  - order status update now stays `pending` locally so sync can upload it

- Added printable/sharable order label support
  - created `lib/services/barcode_service.dart`
  - generates PDF label with:
    - Code128 barcode of order ID
    - QR code for public tracking URL
    - human-readable order details
  - added print and share buttons to `OrderDetailsScreen`

- Added barcode scanning
  - created `lib/screens/scanner_screen.dart`
  - uses `mobile_scanner`
  - **Smart Scanner Logic**: 
    - If scan is a URL (starts with http) -> Opens in external browser.
    - If scan is an ID -> Opens `OrderDetailsScreen` in-app.

- Added cross-browser CSS to `web/track.html`
  - Forces light-mode/black text to prevent "invisible text" on mobile dark-mode browsers.

- Added manual order ID entry
  - `orders_list_screen.dart` now has:
    - scan button
    - manual order ID dialog button

- Added status history UI inside order details
  - `OrderDetailsScreen` now shows a `Status History` card

- Added web tracking page
  - created `web/track.html`
  - loads:
    - order
    - customer
    - participants from `order_assignments` and `users`
    - status history from `statusLogs`

- Updated Firestore rules
  - public read enabled for:
    - `orders`
    - `customers`
    - `users`
    - `order_assignments`
    - `statusLogs`
  - authenticated writes remain enabled

- Added Firebase hosting/index config
  - updated `firebase.json`
  - added `firestore.indexes.json` for `statusLogs(orderId, changedAt)`

- Added platform permissions
  - Android camera permission added
  - iOS camera usage description added

## Files Added

- `lib/services/barcode_service.dart`
- `lib/screens/scanner_screen.dart`
- `web/track.html`
- `firestore.indexes.json`

## Files Updated

- `pubspec.yaml`
- `lib/services/database_helper.dart`
- `lib/services/sync_service.dart`
- `lib/screens/order_details_screen.dart`
- `lib/screens/orders_list_screen.dart`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `firestore.rules`
- `firebase.json`

## Still Required By You

- Run `flutter pub get`
- Rebuild the app
- Deploy Firestore rules and indexes:
  - `firebase deploy --only firestore:rules`
  - `firebase deploy --only firestore:indexes`
- Deploy hosting:
  - `firebase deploy --only hosting`

## Notes

- The tracking URL used in labels is:
  - `https://semerefashions.web.app/track.html?id=<orderId>`
- The tracking page uses Firebase web config based on the current project values in the repo.
- Public read access was widened for tracking; review that decision before production if stricter privacy is needed.
