# Publishing on GitHub

## 1. Create the repository

Create an empty public repository named:

```text
touchlockbuttons.koplugin
```

Do not initialize it with another README, license, or `.gitignore`; those files are already included.

Suggested description:

```text
Experimental KOReader virtual button bar and PW4 Power-button controller with triple-click touchscreen lock.
```

Suggested topics:

```text
koreader kindle paperwhite pw4 lua luajit eink koreader-plugin
```

## 2. Push the prepared source

From the repository directory:

```sh
git init
git add .
git commit -m "Initial public release"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/touchlockbuttons.koplugin.git
git push -u origin main
```

## 3. Confirm CI

Open the **Actions** tab and confirm that **Validate and package** succeeds. The workflow checks Lua syntax, shell syntax, SVG structure, required files, and package integrity.

## 4. Publish v0.1.0

```sh
git tag -a v0.1.0 -m "TouchLockButtons v0.1.0"
git push origin v0.1.0
```

The **Publish tagged release** workflow will:

1. verify that the tag matches `VERSION`;
2. validate the source;
3. create the installable plugin archive;
4. generate its SHA-256 checksum;
5. create a GitHub prerelease and upload both assets.

Versions beginning with `v0.` are automatically marked as prereleases.

## 5. Release asset users should download

Users should install:

```text
touchlockbuttons.koplugin-v0.1.0.zip
```

They should not install GitHub's automatically generated **Source code** ZIP, because it uses the repository name and commit archive layout rather than the deliberately validated release layout.

## Future releases

1. Update `VERSION`.
2. Add the release section to `CHANGELOG.md`.
3. Commit and push the change.
4. Create and push a matching `vX.Y.Z` tag.
