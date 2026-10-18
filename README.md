# RodentStudio · Official Support Website

Static bilingual (English / 简体中文) website for the macOS RodentStudio application, designed to be hosted on GitHub Pages. It contains public **Support URL**, **Privacy Policy URL**, product overview, guide, FAQ, legal notices, accessibility feedback, and release notes.

## GitHub Pages URL after deployment

- Marketing / Product: https://seesaw-earth.github.io/RodentStudio-Support/
- Support URL: https://seesaw-earth.github.io/RodentStudio-Support/support.html
- Privacy Policy URL: https://seesaw-earth.github.io/RodentStudio-Support/privacy.html
- Chinese support: https://seesaw-earth.github.io/RodentStudio-Support/zh/support.html
- Chinese privacy: https://seesaw-earth.github.io/RodentStudio-Support/zh/privacy.html

**URLs become valid only after you deploy GitHub Pages successfully.** Do not enter an unverified URL in App Store Connect.

## Publish with GitHub CLI on your Mac

Unzip this site into `~/Downloads/RodentStudio-Support`. If the folder is present there, run:

```bash
cd ~/Downloads/RodentStudio-Support
gh auth status
git init -b main
git add .
git commit -m "Create RodentStudio macOS support website"
gh repo create seesaw-earth/RodentStudio-Support --public --source=. --remote=origin --push
```

Then open `https://github.com/seesaw-earth/RodentStudio-Support/settings/pages` and choose **Build and deployment → Source: Deploy from a branch → Branch: main → Folder: /(root) → Save**. Wait for Pages deployment, then verify the public URLs above in a private/incognito browser window.

If you already created the repository, use `git remote -v` and `git push origin main` instead of running `gh repo create` again.

## Before submitting to Apple

Read `PUBLISHING_CHECKLIST_CN.md` and `APP_STORE_CONNECT_URLS.md`. Most importantly:

- The policy reflects reviewed *source code* of release candidate 0.6.3; check the final signed build, all third-party components and data flows before claiming “Data Not Collected.”
- The public issue tracker is the provided support channel. Consider adding a publisher-approved support email for sensitive privacy enquiries; don't post sensitive information in public issues.
- Verify you have appropriate rights/licenses for distributing all model weights and included source code (source release LICENSE is AGPL-3.0).
- Do not publish imaginary App Store links or screenshots that do not represent the shipping app. This site deliberately marks the product as preparing for release.
- Update the website when functionality, policy, app availability or support contacts change.

## Maintenance

Edit `.html` files and `assets/styles.css`, then `git add . && git commit -m "Update support website" && git push`. GitHub Pages republishes after changes to `main`. No Node.js, Python, tracking pixels, analytics or build pipeline required to serve the website; The site uses system fonts and loads no third-party scripts, font resources or tracker pixels.
