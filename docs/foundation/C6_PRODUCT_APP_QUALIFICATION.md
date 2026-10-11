# Actual product App qualification — 2026-10-11

The bounded product create/edit workflow and light-mode layout observations passed on source parent9576fc0d9629abbc72ef5510ee9c78147d1d9fb8. This is an actual main/App/AuthProvider/login/shell/routes/form/service/client build using the owned Auth/PostgREST backend; no HTTP, Auth or product service mocks. No production source change.

The protected create route led to login and returned to the form. User input saved a product with its expected SKU/name/base-unit/selling price; its database row was checked. A real edit deep link restored that row, and the actual update button persisted its renamed value. Save/edit ran at1440px/light mode only. No unhandled page error or external HTTP dependency was observed.

A separate layout probe waited relevant animations and fonts before inspection. At390 and900 the main occupies the viewport with its closed drawer outside; at1440 the main occupies1180px and the sidebar260px, with no overlap. RTL and no horizontal overflow were checked at all3 widths. Settled screenshots are saved under evidence/c6-product-form-390.png,900.png and1440.png. Earlier transient clipped screenshots were captured mid-transition and are not accepted visual evidence.

Known limits:4 unread-notification count RPC responses were404 because the fixture lacks source42. Service Workers were blocked and the Realtime backend was absent. Notifications, actual offline/update/Realtime, dark mode, keyboard/touch accessibility, mobile save/edit and unified before/after performance remain open. A single navigation sample proves no speed improvement. This does not accept full App or overall C6/baseline.

Harness corrections are recorded in JSON: NULL decoding, mixed Windows static-server path guard, timestamp cleanup trigger, and the edit button's actual label. The timestamp cleanup mismatch was recovered from the SHA-verified archive; all48 public table rows matched afterward. Corrected runs retired their product, restored profile timestamps and reenabled its trigger, with exact48-table row parity. Browser/server instances ended. Auth session metadata is not a binary restore claim.

Direct Claude read-only evidence review passed with these limits. The next bounded prerequisite is the source42 unread-counter fixture dependency, then the written actual performance/PWA and Realtime gates; do not broaden this into a redesign or notification-system implementation.
