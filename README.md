# DMT Daily Tracker

Daily case tracker for the DMT support desk. Staff log every dealer contact in the CRM log as they work, and the daily totals, team report and dashboard update automatically. Supervisors compile the WhatsApp **DAILY REPORT**, managers watch the dashboard, and everyone can look up live dealer campaigns.

Sign-in uses **Microsoft 365 (Outlook) accounts**. Data and memo files are stored in **Supabase**. The app itself is a single static page, so any static host can serve it.

## What's in the app

| Tab | Who sees it | What it does |
| --- | --- | --- |
| CRM log | Everyone | Log each contact: channel (Call, WhatsApp, Facebook, Email, Walk-in), topic, caller number / WhatsApp number / email / Facebook name, dealer ID, description and status (Resolved, Follow-up needed, Forwarded). Edit or delete entries; look up a dealer's earlier contacts; add issue notes for the daily report. |
| CRM records / My records | Everyone (staff see their own) | Search every logged contact by date, staff, channel, topic, status, number, email, dealer ID or words; export to CSV. |
| My report | Support staff | Their own totals, trend, topics and notes for any date range. |
| Team report | Supervisor, Manager | Who has logged; team totals; ISSUE notes; one-click copy of the WhatsApp DAILY REPORT. |
| Dashboard | Supervisor, Manager | Any date range, team or one staff member: totals vs previous period, daily chart by channel, topic ranking, channel mix, staff productivity, issue-note log. |
| Campaigns | Everyone (supervisors and managers can edit) | Dealer campaigns for Dealer / AD / MD with validity dates, automatic status (Upcoming, Ongoing, Ending soon, Expired), mechanics, reward, memo files (PDF/images), links, notes for staff, CSV export. |
| Team & topics | Manager | Team list with each person's Outlook email and role; topic and channel lists. |

### Access control

- Only people on the team list can use the app. A manager adds each person with their **Outlook email** and a role.
- Staff sign in with **Sign in with Microsoft**. Their email is matched to the team list, and that match decides their role.
- Access is enforced by the database through row-level security in `supabase/schema.sql`, not only by hiding buttons:
  - **Support staff** can read team data but can only create or change **their own** daily entries.
  - **Supervisors** can also correct anyone's entries, write team-report notes, and manage campaigns and memo files.
  - **Managers** can do all of that and also manage the team list, roles, topics and channels.
- Removing someone from the list blocks their access straight away. Their past cases stay in the reports.

### How the automatic totals work

Every time a contact is logged, edited, moved to another day or deleted, a database trigger recounts that staff member's day: the total, the count per channel and the count per topic. The team report, the WhatsApp DAILY REPORT and the dashboard read those counts, so nobody has to tally anything by hand. Issue notes are kept separately and are never touched by the recount.

Days logged before the CRM log existed keep their original totals until a contact is logged on that day.

## Files

```
index.html           the app (HTML, CSS and JavaScript in one file)
config.js            your Supabase URL and anon key (fill in)
supabase/schema.sql  tables, access rules, memo storage, default topics
```

Until `config.js` is filled in, opening `index.html` shows **demo mode** with sample data. Demo mode saves nothing.

## Setup (about 30–45 minutes)

You need: a Supabase account, someone with admin rights in XOX's Microsoft Entra ID (Azure AD), usually IT, and this repo.

### 1. Create the Supabase project

1. Sign in at https://supabase.com and create a **New project**. Pick the **Southeast Asia (Singapore)** region so data stays close to Malaysia.
2. Open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and click **Run**.
3. Add yourself as the first manager. At the bottom of the file, edit the commented `insert into public.team_members ...` line with your name and Outlook email, then run that line on its own.
4. Go to **Project Settings → API** and copy the **Project URL** and the **anon public** key.

### 2. Register the app in Microsoft Entra ID (IT admin)

1. Go to https://entra.microsoft.com → **Applications → App registrations → New registration**.
   - Name: `DMT Daily Tracker`
   - Supported account types: **Accounts in this organizational directory only** (single tenant). This means only XOX accounts can sign in.
   - Redirect URI: platform **Web**, value `https://<your-project-ref>.supabase.co/auth/v1/callback`
2. On the app's **Overview** page, copy the **Application (client) ID** and the **Directory (tenant) ID**.
3. Under **Certificates & secrets → New client secret**, create a secret and copy its **Value** straight away.
4. Under **Token configuration → Add optional claim → ID**, add `email` and `xms_edov`. Supabase needs these to read a verified email.
5. Under **API permissions**, make sure Microsoft Graph `email`, `openid` and `profile` are listed. Grant admin consent if your tenant requires it.

### 3. Turn on Microsoft sign-in in Supabase

1. Go to **Authentication → Sign In / Providers → Azure** and enable it.
2. Fill in:
   - **Client ID** = Application (client) ID
   - **Secret** = the client secret value
   - **Azure Tenant URL** = `https://login.microsoftonline.com/<Directory (tenant) ID>`
3. Go to **Authentication → URL Configuration** and set **Site URL** to where the app will live, for example `https://wendyqiqi1-pixel.github.io/DMT-Tracker/`. Add the same address under **Redirect URLs**.

### 4. Connect the app

Edit `config.js`:

```js
window.DMT_CONFIG = {
  supabaseUrl: "https://<your-project-ref>.supabase.co",
  supabaseAnonKey: "<anon public key>"
};
```

The anon key is meant to be public. Sign-in plus the database rules protect the data. **Never** put the `service_role` key in this repo.

### 5. Publish the site

You have two options:

- **GitHub Pages** (free for public repos): go to repo **Settings → Pages → Deploy from a branch → `main` / root**. The site appears at `https://wendyqiqi1-pixel.github.io/DMT-Tracker/`.
- **Private repo**: GitHub Pages needs a paid GitHub plan for private repos. Instead, connect the repo to **Cloudflare Pages**, **Netlify** or **Vercel** (all free), with no build command and output directory `/`.

Whichever you choose, its address must match the Site URL from step 3.

### 6. Add the team

Sign in as the manager, open **Team & topics**, and add each person with the name used in the report, their Outlook email and their role. Share the site address with them. They click **Sign in with Microsoft** and land on the right view for their role.

### Updating an existing setup

If you already ran `supabase/schema.sql` before the CRM log was added, run the whole file again in the SQL Editor. It's safe to re-run. It adds the `crm_logs` table, its access rules and the automatic-total trigger, and it switches the channels to Call, WhatsApp, Facebook, Email and Walk-in. Your existing team, cases, notes and campaigns are kept.

## Troubleshooting

| What you see | Fix |
| --- | --- |
| "You're signed in, but not on the team list" | The email shown must match the email on the team list exactly. Check for aliases such as `firstname.lastname@` vs `initials@`. |
| Microsoft error `AADSTS50011` (redirect URI mismatch) | The redirect URI in Entra ID must be exactly `https://<project-ref>.supabase.co/auth/v1/callback`. |
| Sign-in returns to the page but stays signed out | Check Site URL and Redirect URLs in Supabase (step 3.3), and that `config.js` has the right URL and key. |
| Error about an unverified or missing email | Add the `email` and `xms_edov` optional claims (step 2.4). |
| "Couldn't load the tracker data" | Run `supabase/schema.sql` again and confirm the first manager row exists. |
| Memo upload fails | Only supervisors and managers can upload. Files must be PDF, PNG, JPG or WEBP, up to 20 MB. |

## Notes

- **Data volume:** the app loads the last 400 days of entries.
- **Older history:** stays in the database and can be exported from Supabase (Table Editor → Export to CSV).
- **Back-ups:** Supabase takes daily back-ups on paid plans. On the free plan, export the tables regularly.
- **Earlier version:** the first version ran as a Claude page and was committed as `daily-case-tracker.html`. That file has been removed from the repo, but it remains in git history.
