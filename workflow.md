# Money Management App: Build Workflow (Roadmap)

Flutter (Android + iPhone) · Firebase backend · amounts stored as integer paise.
Source of truth for requirements: the Product Document (Oct 9, 2026). This file is the execution order.

## How to use this file
- Work phases in order; do not start a phase until the previous "Exit criteria" are met.
- Tick boxes as you go. Each task is sized to roughly 0.5-2 days.
- Keep a short decision log at the bottom for anything that changes the design.

## Phase 0: Foundations and alarm spike (de-risk first)
Goal: prove the riskiest part (alarms) and set up the project skeleton.

- [x] Create Flutter project, set Android/iOS bundle ids, git repo, `.gitignore`
- [x] Create Firebase project (dev and prod), add Android + iOS apps, `flutterfire configure`
- [x] Choose state management (Riverpod recommended) and folder layout (feature-first: `auth/ people/ transactions/ reminders/ reports/ settings/ core/`)
- [x] Confirm current package versions and iOS support (firebase_*, flutter_local_notifications, fl_chart, pdf, csv, flutter_contacts, share_plus)
- [x] CI: `flutter analyze` + `flutter test` on every push
- [x] **Alarm spike (Android):** exact alarm + full-screen intent + boot re-schedule; test app closed, screen locked, after restart, battery saver on
- [ ] (deferred: needs a Mac + iPhone) **Alarm spike (iPhone):** AlarmKit bridge on a real device; confirm minimum iOS version; local-notification fallback (about 30 s sound)
- [ ] (deferred: needs the phones; Xiaomi 23127PN0CG / Android 16 in progress) Test on Xiaomi, Oppo, Vivo, Samsung; record per-brand permission steps
- [ ] Write the decision: iPhone approach, minimum iOS version

### Android alarm spike results
| Device | Android | Result |
| --- | --- | --- |
| Xiaomi 23127PN0CG | 16 (SDK 36) | Passed (manual test by user): full-screen alarm screen with sound, Snooze and Dismiss; app closed, locked, reboot, battery saver. Needed Xiaomi autostart + lock-screen permissions. |

### Package versions (confirmed 2026-10-09, Flutter 3.44.1)
| Package | Version | iOS min | Notes |
| --- | --- | --- | --- |
| firebase_core / auth / cloud_firestore / storage / messaging | 4.15 / 6.7 / 6.10 / 13.6 / 16.7 | 15.0 | iOS target raised from 13.0 to 15.0 |
| flutter_riverpod | 3.4.3 | n/a | |
| flutter_local_notifications | 22.3.1 | 13.0 | Android needs core library desugaring (enabled in `android/app/build.gradle.kts`) |
| flutter_contacts | 2.6.0 | 13.0 | |
| share_plus | 13.3.1 | 13.0 | |
| fl_chart / pdf / csv | 1.2.0 / 3.13.1 / 8.0.0 | n/a | pure Dart |

Exit criteria: alarm rings on a real Android phone and a real iPhone with the app closed; iPhone approach decided.

## Phase 1: MVP (core ledger)
Goal: a usable lent/borrowed tracker with sync and security.

1. Data layer
   - [x] Money type (int paise) + formatter (₹, Indian/western grouping)
   - [x] Firestore models + repositories: users, people, transactions, payments
   - [x] Enable offline persistence
   - [x] Payment write = Firestore transaction updating `paidTotal`, `balance`, `status` together
   - [x] Status engine (Pending / Partially Paid / Overdue / Paid, overdue priority) with unit tests
   - [x] Block overpayment
2. Auth
   - [x] Sign up (name, email, password) + verification email
   - [x] Login, logout, forgot password
   - [x] Profile: name, currency, timezone
   - [x] Delete account (client flow; function cleanup comes in Phase 2)
3. Security
   - [x] Firestore + Storage rules (own uid + email_verified) (Firestore rules deployed 2026-10-09; Storage rules written and tested, deploy once Storage is enabled)
   - [x] Rules tests with the emulator (cross-user read/write denied)
4. People
   - [x] People list: initials avatar, net amount colours, search, filters, sort
   - [x] Add/edit/delete person
   - [x] Name autocomplete with recent-first, balance, and "Add 'Name' as new person"
   - [ ] Person ledger timeline with running balance
5. Transactions
   - [x] Add entry screen (Lent / Borrowed segmented), amount, dates, notes
   - [x] Entry detail: progress bar, payment list, Receive Payment / Pay Now bottom sheet
   - [x] Edit/delete a payment; recompute balance from payments
   - [ ] Optional interest on borrowed (simple, compound) and repayment type
6. History
   - [ ] Settings → History: settled entries, filters, search
   - [ ] "Mark as unpaid" with confirmation
7. Shell
   - [ ] Bottom nav (Home, People, +, Reminders, Settings), theme tokens (light/dark palette), basic Home totals

Exit criteria: testing-checklist items for partial payments, overpayment block, History/unpaid, autocomplete, offline sync, and security rules all pass. Internal build on both platforms.

## Phase 2: EMI, instalments, reminders, dashboard
Goal: scheduled payments and alarms.

- [ ] Schedule engine (pure Dart, heavily tested): EMI formula, 0% case, principal/interest split, month-end date clamping, last-EMI rounding fix
- [ ] Validate EMI against a bank calculator for 3+ loans (incl. 0%)
- [ ] EMI purchase form + schedule screen (green/amber/red dots, summary card)
- [ ] Mark single EMI paid (date, amount, mode)
- [ ] Pay-to-person instalments: generate, skip month, change amount, extra payment
- [ ] Foreclosure / part-prepayment calculator (labelled as estimate); late fee and no-cost EMI options
- [ ] Reminders: CRUD, repeat rules, snooze (5/10/15), custom tone/volume/vibration
- [ ] Production alarm service from Phase 0 spike; re-schedule on boot and on app start
- [ ] Auto reminders for linked payments: 1 day before, due day, overdue
- [ ] Upcoming / Completed / Missed lists; "Notification permission help" screen
- [ ] FCM push + Cloud Functions: scheduled overdue/status job, account-deletion cleanup
- [ ] Dashboard: net card, To receive / To pay, Overdue / This week / This month, upcoming list, FAB with all entry types

Exit criteria: alarm checklist passes on 3+ Android brands and an iPhone; EMI dates correct for 29th/30th/31st; delete account wipes Firestore + Storage.

## Phase 3: Reports, export, polish
- [ ] Reports: monthly summary, owe vs receive chart, EMI burden, 6-month outflow forecast, top people (fl_chart)
- [ ] PDF/CSV export for reports and History
- [ ] Photo attachments (bills, payment screenshots) via Storage
- [ ] Person statement share (PDF / WhatsApp text); send reminder to person (WhatsApp/SMS/link)
- [ ] Contacts import and duplicate-person merge
- [ ] Settings: currency/number/date format, default reminder timing, theme, quiet hours, daily/weekly summary, backup/export, privacy/about
- [ ] Swipe actions, empty states, success animation, accessibility (large fonts, dark mode contrast)
- [ ] Standalone EMI and interest calculators; categories/tags; audit log

Exit criteria: full testing checklist (section 9.2 of the product doc) green; no layout breaks at large font sizes.

## Phase 4: Release
- [ ] Privacy policy URL, in-app + web account deletion link
- [ ] Play Console: data safety form, exact-alarm and full-screen-intent justification, internal testing track
- [ ] App Store: privacy details, notification/alarm permission text, TestFlight
- [ ] Re-check current store fees and policies before submitting
- [ ] Crash reporting + analytics, production Firebase config, rules deployed
- [ ] Submit, monitor, hotfix window

## Phase 5: Later (post-launch)
- [ ] Shared ledger (other person confirms entries)
- [ ] Home screen widget with upcoming dues
- [ ] Multiple currencies, business/personal mode
- [ ] Languages: Malayalam, Hindi
- [ ] Recurring bills (rent, subscriptions)
- [ ] Rule field validation (amount > 0, valid status)

## Risks to watch
| Risk | Mitigation |
| --- | --- |
| Android OEMs kill background alarms | Phase 0 brand testing, battery-exemption onboarding |
| AlarmKit needs recent iOS | Decide min iOS in Phase 0; local-notification fallback |
| Money rounding errors | Integer paise everywhere; schedule rounding goes into the last EMI |
| Stale denormalised data (`personName`, totals) | Update in the same write / batch; add a repair function |
| Store rejection | Account deletion, privacy policy, permission justifications prepared early |

## Decision log
| Date | Decision | Reason |
| --- | --- | --- |
| 2026-10-09 | Flutter + Firebase, email/password only, no app lock | Product doc |
| 2026-10-09 | iOS deployment target 15.0 | Required by firebase_* 4.x-16.x plugins |
