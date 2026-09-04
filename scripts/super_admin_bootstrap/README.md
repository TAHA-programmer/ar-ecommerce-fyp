# Super Admin bootstrap (Phase 8.4) — manual procedure

This promotes exactly one real account to Super Admin. It is a one-time,
developer-only, local-only operation — not Flutter app code, not a Cloud
Function, not deployed anywhere, and not reachable from the mobile app.
There is no in-app "invite an admin" feature by design.

## 1. Create the account you want as Super Admin

Sign up through the TWin AR app itself (real Sign Up screen), using
whichever email/password you want for your admin account. This creates:

- a real Firebase Authentication account, and
- a `users/{uid}` Firestore document with `role: 'customer'` (every signup
  defaults to customer — there is no way to sign up as admin).

Log in once afterward to confirm the account works normally as a customer.

## 2. Find its UID

Firebase Console → Authentication → Users tab → find the row for the email
you just used → copy the value in the "User UID" column.

## 3. Configure Firebase Admin credentials (local machine only)

Pick ONE:

**Option A — Application Default Credentials (recommended if you're already
`firebase login`'d as an Owner/Editor on this project):**

```bash
gcloud auth application-default login
```

This opens a browser sign-in and stores a short-lived credential in your
user profile — nothing is written into this repo.

**Option B — a service-account key**, if Option A isn't available to you:

1. Firebase Console → Project Settings → Service Accounts → "Generate new
   private key" → downloads a `.json` file.
2. Save it somewhere **outside this repository** (e.g. your home
   directory), never inside `twin_ar/`.
3. Never commit it, never put it in Flutter assets, never paste its
   contents anywhere (chat, issue tracker, etc.).
4. Point the script at it for the session:
   - PowerShell: `$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\key.json"`
   - bash: `export GOOGLE_APPLICATION_CREDENTIALS="/c/path/to/key.json"`

## 4. Run the promotion script

```bash
cd scripts/super_admin_bootstrap
npm install
node promote_super_admin.mjs <uid-from-step-2> --confirm
```

It will:
- set the Firebase Auth custom claim `{role: 'superAdmin'}` on that account
  (the real authorization boundary), and
- update that account's `users/{uid}.role` Firestore field to `'superAdmin'`
  (the UI-convenience mirror only).

The script refuses to run without `--confirm`, and aborts with no changes
if the uid doesn't exist.

## 5. Sign out and sign back in

Custom claims are only read from a **fresh** ID token. On the device/app
session where you're testing:

1. Log out of the account (Profile → Log Out).
2. Log back in with the same credentials.
3. You should now land on the Admin Dashboard instead of Customer Home.

If you were still signed in on a different device with that account, that
session keeps its old (customer) claim until it also signs out and back in.
