# Upload this existing project safely

The inspected branch is `main`. Its existing `origin` points to
`https://github.com/InlitX/streak.git` for fetch and push. The reported 403 means
the authenticated `MajedStore` account cannot push there. Local preparation does
not grant that permission; no remote was changed and nothing was pushed.

Use an empty repository you own, such as `MajedStore/level-up`, while retaining
the current project history and the original project as `upstream`. A new
repository is needed only if you do not obtain write access to the existing one
or already have an appropriate repository under your account.

## What was checked locally

- The initial working tree was clean. Three local commits follow the inspected
  upstream baseline `23b32102a394228d528403c9f6d48dccc9eb0316`.
- The real `backend/.env` exists, is ignored, and is not tracked. Its values were
  inspected only in memory for the audit and were not printed or copied.
- The tracked `backend/.env.example` contains placeholder URI/secret values.
- No tracked dependency directories, generated build directories, signing keys,
  machine-specific properties, or local database files were found.
- All reachable Git history is checked as well as the index, tracked working
  files, and untracked files eligible for upload. Removing a secret from the
  current file would not conceal a historical leak from this check.
- `.env*` files, including editor-created copies, are now ignored everywhere.
  Only the exact `.env.example` name is allowed, and its contents are audited.

The audit is a local preflight, not a guarantee that arbitrary future secrets
will be recognized. It checks exact sensitive values from local environment
files, credential-bearing URLs, recognizable tokens, private keys, and unsafe
file paths. It does not contact GitHub, Render, or Atlas.

## 1. Create your repository manually

Sign in to GitHub as `MajedStore`, choose **New repository**, and create
`level-up`. Leave **Add a README**, **Add .gitignore**, and **Choose a license**
unselected: those files and the history already exist here. Choose repository
visibility according to your needs. Preserve the existing GPL-3.0-only license
and attribution notices; a new GitHub repository does not replace them.

Do not run the next remote commands until that real empty repository exists and
you have confirmed the owner/name. If you choose another name, substitute it in
the `git remote add` command.

## 2. Connect it without discarding history

From PowerShell in the existing project folder:

```powershell
git branch --show-current
git remote -v
git status --short
git remote rename origin upstream
git remote add origin https://github.com/MajedStore/level-up.git
git remote -v
```

These commands are for you to run after repository creation. They have not been
run automatically. The rename preserves the original repository URL. If an
`upstream` remote already exists by then, inspect it first and choose an unused
name; do not overwrite an unrelated remote. Do not force-push or reinitialize
the repository.

## 3. Audit and review the upload

Keep the real `backend/.env` on this computer. Never force-add it, paste its
contents into an issue, or use it as an Android build input. Set its secret
values separately in the Render dashboard.

```powershell
node --test scripts/check-upload-safety.test.mjs
node scripts/check-upload-safety.mjs
git check-ignore -- backend/.env
git status --short
```

The safety script must end with `"result":"PASS"` and exit zero. It prints
only categories, paths, line numbers, redacted markers, and counts. Exit 1 means
the upload is blocked by a finding; exit 2 means the check could not finish.
It deliberately scans untracked nonignored files, so staging everything is not
required to inspect the prepared deployment files.

If it reports a real secret in history, stop before pushing. Rotate that
credential and decide how to clean or replace the affected history. This
project's preparation does not automatically rewrite history or remove data.

Stage the reviewed deployment changes explicitly, then audit the index too:

```powershell
git add -- .gitignore .github/workflows backend docs render.yaml scripts README.md
git diff --cached --name-only
node scripts/check-upload-safety.mjs
git commit -m "Prepare Level Up deployment"
```

Ignored dependencies, environment files and build outputs remain on disk and
are excluded. Do not add `-f` or use a wildcard to force private files into Git.
If you make additional source changes, audit them and stage those exact paths
before committing.

## 4. Push only to your confirmed repository

```powershell
git remote get-url origin
git push -u origin main
```

Confirm that the URL printed immediately before the push is your own repository.
Authenticate through Git's credential manager or GitHub's normal login flow if
prompted. Never put a password or token directly in the remote URL. If a 403
remains, resolve access with the repository owner/account settings; no command
here bypasses GitHub permissions.

After upload, connect this repository to a Render **Web Service** using
[the backend deployment instructions](../backend/RENDER.md). Configure secrets
only in Render. Follow [the Android deployment instructions](DEPLOYMENT_ANDROID.md)
after the real HTTPS service URL exists. Uploading the source by itself does not
deploy the API or verify Atlas connectivity.
