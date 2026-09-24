# Door Scheduler V2: one-off Firebase setup

This creates a **new, separate** Firebase project for V2. The live V1 project (`matrix-doorschedulequotation`) is not touched at any point.

When you've done the steps below, every push to the V2 branch deploys automatically through GitHub Actions. You won't need to install anything on your PC.

**It takes about 30 minutes.** You'll need to be able to:
- create Google Cloud / Firebase projects;
- add a card for billing;
- change settings on the `harveydove-mtx/door-scheduler` GitHub repo.

> **Names matter.** Anything shown in `code style` must be typed exactly, because the repo expects those names.

---

## 1. Create the project and turn on billing (Blaze)

1. Go to <https://console.firebase.google.com> and choose **Create a project**.
2. Name it **Matrix Door Scheduler V2**. Firebase suggests a project ID from the name, e.g. `matrix-door-scheduler-v2`; it may add a suffix if the ID is taken. **Write the project ID down.**
3. Google Analytics isn't needed, so turn it off, then choose **Create project**.
4. In the bottom-left, choose **Upgrade** and pick the **Blaze (pay as you go)** plan. The SQL database needs this.
5. Set a budget alert:
   1. Google Cloud console → **Billing** → **Budgets & alerts** → **Create budget**.
   2. Set it for this project at **£20 / month**, with email alerts at 50%, 90% and 100%.
   3. A budget only sends alerts; it doesn't stop anything.

## 2. Sign-in: email and password, staff accounts only

1. Firebase console → **Build → Authentication → Get started**.
2. On **Sign-in method**, choose **Email/Password** → **Enable** → Save. Leave "Email link" off.
3. On **Settings → User actions**, **untick "Enable create (sign-up)"** and save. This means only accounts you create can sign in.
4. On **Users → Add user**, add each person with their `@matrixhardware.co.uk` email and a temporary password.
   - Staff can change their password with **Forgot password?** on the sign-in page.
   - The app refuses any email outside `@matrixhardware.co.uk`, even if an account exists for it.

## 3. The SQL database (Data Connect)

1. Firebase console → **Build → Data Connect → Get started**.
2. Enter these values **exactly**:

   | Setting | Value |
   |---|---|
   | Location / region | `europe-west2` (London) |
   | Cloud SQL instance ID | `door-scheduler-sql` |
   | Database name | `doorscheduler` |
   | Service ID | `door-scheduler` |

3. If you're offered the **no-cost trial** Cloud SQL instance, take it. Otherwise choose the smallest instance (about £8–15 a month).
4. If it offers to create a sample or template schema, **skip it / start empty**. The repo brings its own database.
5. Creating the Cloud SQL instance takes a few minutes. Wait until it shows as ready.

## 4. Register the web app and send me its config

1. Firebase console → ⚙️ **Project settings** → **General** → **Your apps** → **Web** (the `</>` icon).
2. Nickname: **Door Scheduler V2**. Leave "Firebase Hosting" unticked, because the repo sets that up. Choose **Register app**.
3. Firebase then shows a `firebaseConfig` block. Copy the **apiKey**, **authDomain**, **projectId** and **appId** values and paste them into our chat.
   - These values aren't secret: they identify the project, and access is controlled by sign-in.
   - I'll put them in `app/.env.production`.

## 5. A key for GitHub to deploy with

1. Open <https://console.cloud.google.com/iam-admin/serviceaccounts> and make sure the **V2 project** is selected at the top.
2. **Create service account**:
   - Name: `github-deployer`
   - Description: "Deploys Door Scheduler V2 from GitHub Actions"
3. Give it these three roles:
   - **Firebase Admin**
   - **Cloud SQL Admin**: sets up database permissions and applies database updates.
   - **Service Usage Consumer**
4. Choose **Done**. Open the new account → **Keys** → **Add key → Create new key → JSON**. A file downloads.

## 6. Give GitHub the key and the project ID

On GitHub, open `harveydove-mtx/door-scheduler` → **Settings → Secrets and variables → Actions**.

1. On the **Secrets** tab, choose **New repository secret**:
   - Name: `FIREBASE_SERVICE_ACCOUNT_V2`
   - Value: open the downloaded JSON file in Notepad and paste **the whole contents**.
2. On the **Variables** tab, choose **New repository variable**:
   - Name: `FIREBASE_PROJECT_ID_V2`
   - Value: `matrixdoorschedulerv2` (the V2 project ID).
3. **Delete the downloaded JSON file** from your PC, including from the recycle bin. GitHub keeps it encrypted, and nobody needs another copy.

## 7. Tell me it's done

Send me the web config (step 4) and the project ID. I'll then:
1. commit `app/.env.production`;
2. push, which starts **V2 deploy** in the repo's **Actions** tab.

That first deploy:
- sets up the database permissions;
- creates all the tables and loads the starting rates (the V1 defaults);
- deploys the app.

When it finishes, the app is at **<https://matrixdoorschedulerv2.web.app>**. Sign in with an account from step 2 and start filling in MAT codes and prices.

A custom address such as `scheduler-v2.matrixhardware.co.uk` is added later (Hosting → Add custom domain, plus two DNS records).

---

## How it fits together

```
GitHub push ──> "V2 checks" workflow (always): database tests, app tests, emulator tests
            └─> "V2 deploy" workflow (once set up):
                  1. firebase dataconnect:sql:setup     database roles (safe to repeat)
                  2. db/migrate.sh                      new migrations only; seed on a new database
                  3. firebase deploy dataconnect,hosting
Browser ──sign in──> Firebase Auth (Matrix accounts only)
        ──operations──> Data Connect ──SQL──> Cloud SQL Postgres (europe-west2)
```

- **Only the V2 project:** the deploy workflow refuses to run against the V1 project ID. It also checks that `app/.env.production` is for the same project it's deploying to.
- **Database changes** are new files in `db/migrations/`. Each one is applied once, and editing a file that's already been applied is refused. The starting data (`db/seed.sql`) is only loaded into a brand-new, empty database. Live data is never overwritten by a deploy.
- **Backups:** Cloud SQL takes automatic daily backups. Check this under Cloud SQL → `door-scheduler-sql` → Backups.

## Looking at the data directly

- **In the app:** the **MAT codes & rates** and **Products** pages.
- **As SQL:** Firebase console → Data Connect → your service → **Data** tab. Or Google Cloud console → **SQL → door-scheduler-sql → Cloud SQL Studio**.
- **Take care with edits in SQL Studio:** they skip the app's checks. Prefer the app, or ask me for a migration.

## Troubleshooting

| What you see | What to do |
|---|---|
| "V2 deploy skipped: not set up yet" in Actions | Normal until steps 4–6 are done. The message lists what's missing. |
| Deploy fails at "Set up Data Connect SQL roles" with a permission error | Check the service account has **Cloud SQL Admin** (step 5). |
| Deploy fails with "instance not found" | Check the names in step 3 match exactly. |
| Signing in says "Signed out: Your account is not allowed" | The email isn't `@matrixhardware.co.uk`. |
| "That email or password is not right" | Check the account exists in Authentication → Users, or use Forgot password. |
