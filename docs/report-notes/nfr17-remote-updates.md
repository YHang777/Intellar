# NFR17 — Remote updates without reinstalling (report note)

**Requirement (3.7.6):** "The system shall support remote updates and bug fixes
without requiring users to reinstall the application."

## How the implemented system meets it

Most of the system's behaviour lives outside the installed app and is updated
remotely, with no action from users:

- **Backend (Node.js on Render).** Business rules for checkout and payments,
  refunds, stock reservation, notifications, the AI design assistant, photo
  analysis, 3D model generation, saved-design access and product-view counting
  all run on the server. Every change pushed to the main branch is built and
  deployed automatically, and takes effect for all users at once.
- **Data and access rules (Firebase).** Firestore security rules and indexes
  are deployed from the repository (`firebase deploy`) and apply immediately
  to every client.
- **Live configuration and content.** Product listings, categories, store
  profiles, the tax rate (admin Settings) and the AI model are read at run
  time, so changing them needs no app update.
- **Admin console.** The web console is served by the same backend deploy, so
  it is updated in place.

## Limitation and future work

Changes to the mobile app's own interface or on-device logic (Flutter code)
still need a new build through the app store, as for any native app. Two
options would extend remote updating to that layer:

1. **Feature flags (Firebase Remote Config):** switch features on or off, or
   tune values, remotely without a release.
2. **Code push (e.g. Shorebird for Flutter):** ship Dart code patches to
   installed apps without a store release.

These were judged unnecessary for the project's scope, because the parts most
likely to need urgent fixes (payments, access rules, AI behaviour) are already
server-side and update remotely.
