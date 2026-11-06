# Authentication setup (Apple · Google · Email)

All three methods use the same Supabase Auth user; `profiles.id` = `auth.users.id` (created by the `handle_new_user` trigger).

## Redirect URLs (Supabase → Authentication → URL Configuration → Redirect URLs)
Add exactly:
- `com.along.app://auth/oauth`
- `com.along.app://auth/verify`
- `com.along.app://auth/recovery`

The URL scheme `com.along.app` (the bundle id) is registered in `project.yml` (`CFBundleURLTypes`).

## Google
1. Google Cloud Console → APIs & Services → OAuth consent screen (External, add app name/support email).
2. Credentials → Create OAuth client ID → **Web application**. Authorized redirect URI:
   `https://zcclkvnqtuppclvfbuuf.supabase.co/auth/v1/callback`
3. Supabase → Authentication → Providers → Google → enable, paste Client ID and Client Secret (secret lives only in Supabase).
No iOS client ID or Google SDK is needed: the app uses `ASWebAuthenticationSession` via supabase-swift.

## Email
Supabase → Authentication → Providers → Email: enabled, **Confirm email ON** (it is on now).
Sign In / Providers → set minimum password length (the app enforces 8 client-side; the server's rule wins).
Customise templates if wanted; the default SMTP is rate-limited — configure custom SMTP before launch.

## Apple
Providers → Apple → enable; Client IDs: `com.along.app`. Set your Development Team in Xcode (Sign in with Apple capability is in the entitlements).
For account deletion, Apple requires token revocation (needs the Apple key/secret; not implemented client-side).

## Legal links
Set `LEGAL_TERMS_URL` / `LEGAL_PRIVACY_URL` in `Config/Secrets.xcconfig` (`https:/$()/…`). Until set, the footer text is not linked.

## Account linking
Supabase's default automatic linking (same *verified* email across providers) applies; the app never merges by email itself.
