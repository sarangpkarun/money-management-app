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
   - [x] Person ledger timeline with running balance (statement sharing is Phase 3)
5. Transactions
   - [x] Add entry screen (Lent / Borrowed segmented), amount, dates, notes
   - [x] Entry detail: progress bar, payment list, Receive Payment / Pay Now bottom sheet
   - [x] Edit/delete a payment; recompute balance from payments
   - [x] Optional interest on borrowed (simple, compound) and repayment type (repayment type is recorded only; schedules come with the Phase 2 instalment engine)
6. History
   - [x] Settings → History: settled entries, filters, search (opens from the temporary home until the Settings tab exists; PDF/CSV export is Phase 3)
   - [x] "Mark as unpaid" with confirmation (removes the last payment)
7. Shell
   - [x] Bottom nav (Home, People, +, Reminders, Settings), theme tokens (light/dark palette), basic Home totals (Reminders is a placeholder until Phase 2; Inter/Poppins font and the Light/Dark/System setting come in Phase 3)

Exit criteria: testing-checklist items for partial payments, overpayment block, History/unpaid, autocomplete, offline sync, and security rules all pass. Internal build on both platforms.

**Phase 1 exit check (2026-10-09): all build items done; remaining checks are manual**
- [x] Partial payments, overpayment block, History and "mark as unpaid", autocomplete: covered by automated tests and tried on the Xiaomi phone as each feature landed
- [x] Security rules: 13 emulator tests pass; Firestore rules deployed (Storage rules deploy when Storage is enabled)
- [ ] Offline sync: add entries with no internet on the phone, then confirm they sync
- [ ] Two-account check on the real project: one user cannot see another's data
- [ ] Internal build on iPhone (needs a Mac; Android debug build works)


## Phase 2: EMI, instalments, reminders, dashboard
Goal: scheduled payments and alarms.

- [x] Schedule engine (pure Dart, heavily tested): EMI formula, 0% case, principal/interest split, month-end date clamping, last-EMI rounding fix (`lib/core/emi/`; no screens or storage yet)
- [x] Validate EMI against a bank calculator for 3+ loans (incl. 0%) (checked against published tables from Scripbox, NoBroker and StockCalc, 14 loans, all EMIs match; these are finance-site calculators, not a bank's own, and the 0% case is checked by arithmetic. Optional: confirm one loan against your own bank's calculator)
- [x] EMI purchase form + schedule screen (green/amber/red dots, summary card) (bill photo comes with attachments in Phase 3)
- [x] Mark single EMI paid (date, amount, mode) (part payments allowed; edit/delete a payment reverses its instalment)
- [x] Pay-to-person instalments: generate, skip month, change amount, extra payment
- [x] Foreclosure / part-prepayment calculator (labelled as estimate); late fee and no-cost EMI options
- [x] Reminders: CRUD, repeat rules, snooze (5/10/15), custom tone/volume/vibration (data, repeat engine and screens; nothing rings until the alarm service item below)
- [x] Production alarm service from Phase 0 spike; re-schedule on boot and on app start (user-tested on the Xiaomi: rings with sound and full screen when the phone is locked; while the phone is in use Android shows only a pop-up, which is normal)
- [ ] Auto reminders for linked payments: 1 day before, due day, overdue (code done and tested; tick after checking on the phone)
- [ ] Upcoming / Completed / Missed lists; "Notification permission help" screen (code done and tested; tick after checking on the phone)
- [ ] (deferred by the user: Cloud Functions need the paid Blaze plan and no server push is wanted for now) FCM push + Cloud Functions: scheduled overdue/status job, account-deletion cleanup
- [ ] Dashboard: net card, To receive / To pay, Overdue / This week / This month, upcoming list, FAB with all entry types (code done and tested; tick after checking on the phone)

Exit criteria: alarm checklist passes on 3+ Android brands and an iPhone; EMI dates correct for 29th/30th/31st; delete account wipes Firestore + Storage.

## Phase 3: Reports, export, polish
- [ ] Reports: monthly summary, owe vs receive chart, EMI burden, 6-month outflow forecast, top people (fl_chart)
- [ ] PDF/CSV export for reports and History
- [ ] Photo attachments (bills, payment screenshots) via Storage
- [ ] Person statement share (PDF / WhatsApp text); send reminder to person (WhatsApp/SMS/link)
- [ ] Contacts import and duplicate-person merge (code done and tested; tick after checking on the phone)
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
| 2026-10-09 | Interest is simple/compound on the original principal from the entry date, computed not stored, and frozen at `settledAt` once paid; payments are limited to principal + interest to date | Product doc 8.5; keeps a paid entry from reopening as interest accrues |
| 2026-10-09 | "Mark as unpaid" removes the most recent payment (latest date, then the one recorded last) after a confirmation; History is just entries whose status is Paid | Balance is derived from payments, so reopening must remove one; no data is moved between collections |
| 2026-10-09 | Person ledger running balance uses the People-list convention (positive = they owe you). Interest is its own row (dated today while open, the settled day once paid; before payments on the same day) so the last balance equals the header net | Keeps the ledger, the People list and the entry totals consistent |
| 2026-10-09 | App shell: NavigationBar with a centre "+" that opens an add sheet instead of switching tabs; tabs kept alive with IndexedStack; theme from the product palette following the system light/dark setting | Simple and robust; the Light/Dark/System setting and custom font are Phase 3 |
| 2026-10-09 | EMI schedule: whole-paisa maths, EMI and each month's interest rounded half-up, last instalment clears the balance; due dates measured from the original start day. The last EMI differs from the regular one by up to about ((1+r)^n - 1)/r paise (n paise at 0%), not just n paise | Rounding error compounds with rate and tenure; found while testing a Rs 1,000 loan at 24% for 84 months |
| 2026-10-09 | An EMI purchase is an `emi` transaction: store or bank is a Person, `totalAmount` = total payable (down payment not owed, interest inside the instalments), and the schedule lives in a `schedule` ARRAY on the transaction document (not the `schedule/{id}` subcollection of the product doc) with `dueDate` kept equal to the next unpaid instalment | A Firestore transaction cannot query a subcollection, and a payment must update the instalment, the totals and the next due date atomically; 600 rows is about 60 KB, far under the 1 MB document limit |
| 2026-10-09 | Pay-to-person instalments reuse the EMI plan (`instalment` transaction, rate 0). Skip moves the chosen payment and later unpaid ones a month on (anchored to the start day); change amount re-spreads the rest; an extra payment is baked into the schedule by shrinking from the LAST payment backwards, and deleting it refills the last payment to the regular amount then adds payments of that size. Row numbers are never reused. Invariant: unpaid rows always sum to total minus paid | Keeps one atomic write per change and the original shape of the plan after an undo |
| 2026-10-09 | Foreclosure and part-prepayment are an estimate-only calculator (nothing saved): foreclosure = principal still owed + a charge %, without interest for the part-month already run; part-prepayment shows either the same EMI with fewer months or the same months with a lower EMI. Late fee (flat or % of the instalment, grace days, once per late instalment) and a no-cost EMI's seller-absorbed interest are shown as estimates and never added to what is owed, the status or the payment limits | User choice: keeps balances exact; a lender's own figures differ in fees and day-counting |
| 2026-10-09 | Reminders are split: this item stores them (Firestore `reminders`, repeat rules once/daily/weekly/monthly/yearly/every N days, snooze 5/10/15, tone, vibration, volume) and lists/edits them; scheduling alarms, boot reschedule and applying tone/volume are the next item. Repeats step by calendar day so daylight saving never moves the wall-clock time; monthly/yearly measure from the first ring so a 31st returns after short months; weekly rings only on the chosen weekdays (the first ring counts only if its weekday is chosen) | User choice: keeps the risky alarm work on real-phone testing in its own step |
| 2026-10-10 | Alarm service: each reminder is scheduled as its next up to 30 rings within 60 days (soonest 200 overall), re-synced on every app start and every reminders change; alarm ids are a 26-bit reminder key plus a 5-bit slot (slot 31 = snooze) so no id map is stored; the payload carries title/notes/snooze/tone/vibration/time so the ring screen and the Snooze action work with no database; tone x vibration is one notification channel each (9). The Volume setting was REMOVED: Android cannot set a per-alarm volume while the app is closed, so rings follow the phone's alarm volume. Dismissing a one-off marks it done | User choice; keeps rings reliable. Known limit: a daily reminder rings about 30 days without the app being opened |
| 2026-10-10 | Auto payment reminders are computed from the entries, not stored as reminder documents: for each unpaid EMI/instalment row, or an entry's due date, alarms at 9:00 the day before, on the day, and the day after (overdue, once). A per-entry `autoReminders` switch (default on) turns them off. They share the alarm plan, the 60-day window and the 200 cap; a pending snooze is kept while the entry is open. 9:00 is fixed until the Settings phase | User choice; nothing extra to sync or clean up, alarms follow payments, edits and deletes automatically |
| 2026-10-10 | Reminders tab has three lists. Upcoming = next ring of each manual reminder plus automatic payment alarms in the next 14 days; Completed = done reminders; Missed = one-off reminders whose time passed without being marked done (a repeating reminder is never missed, and automatic payment alarms are not tracked as missed because the phone cannot tell whether a ring was heard). The help screen reads notification and exact-alarm status live, links to the right settings pages through `app_settings`, and shows per-brand steps (Xiaomi tried, others marked untried) | Keeps the lists honest about what the app can know |
| 2026-10-10 | FCM push and Cloud Functions are deferred: they need the Blaze plan, and the user wants no server push for now. Local alarms are the only reminder mechanism. The client already erases a user's Firestore data on account deletion; Storage cleanup is added with attachments (Phase 3). Revisit before release if a server job is wanted | User decision |
| 2026-10-10 | Dashboard sections come from payments, not entries: each unpaid EMI/instalment row, or an entry's own due date, is one item (amount = what is left, interest included for entries). Four disjoint buckets by calendar day: Overdue (before today), This week (today to Sunday), This month (the rest of the month), Upcoming (later). Home and Reminders got unique FAB hero tags because both live in the shell's IndexedStack | Counts each payment once; avoids a page-transition crash with two floating buttons |
| 2026-10-10 | Contacts import and duplicate merge were done before Reports (user's order). Import is opt-in: a screen that asks for READ_CONTACTS only when opened, lists contacts with checkboxes and creates only the ticked people; a no-permission native picker is the fallback and fills the Add person form. Numbers match on their last 10 digits and names ignoring case/spacing. Merge moves all entries to the kept person (renaming them), fills a missing phone/photo, keeps all notes, and deletes the others last so an interrupted merge is safe to re-run; it cannot be undone | Privacy-first import; entries are never left pointing at a deleted person |
