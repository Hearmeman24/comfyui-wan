# Workflow publishing

GitHub is the workflow CMS. Publish through a pull request in this template repository.

1. Put the ComfyUI workflow JSON under `workflows/`. Every JSON in that directory must have exactly one entry in root `catalog.json`.
2. Add the catalogue entry in the same PR: stable `id`, exact `file` path, title, description, model, output, tags, `status: "published"`, `publishedAt` (UTC ISO date), difficulty (`Beginner` or `Advanced`), and nonempty `inputs`/`outputs` arrays (`Text`, `Image`, `Video`, `Audio`, `Reference pack`). Notes are optional. Optional cover images belong under `catalog/assets/`. Do not include credentials, personal paths or private prompts.
3. Preserve existing IDs and publication dates when updating a workflow. Dates describe original publication, not the latest edit. A new workflow needs a real nonfuture date so website Recent/New works.
4. Run the shared catalogue validator before pushing. The `catalog-check` GitHub Actions job uses the same validator and is required before merging; it checks complete file coverage, metadata, safe paths and JSON structure without building the website.
5. Merge the passing PR. `website-content.yml` requests the central `publish-template.yml` workflow in `Hearmeman24/hearmemanai-platform`. It imports the exact source commit into a content-only platform PR. Passing platform checks permit its merge and CircleCI deploys the website.
6. Check the central publishing run and platform PR, then verify the workflow page and download. A successful dispatch is only a request, not proof of deployment. The publishing run verifies the live source and download hashes before reporting success. If publishing fails, fix the source PR or rerun the notification on the latest default branch; do not edit generated platform catalogue files manually.

Never add workflow JSON without catalogue metadata, bypass the required check, or publish directly to the platform's generated catalogue. Workflow relationships and optional guide links remain platform-managed. Workflow updates must not modify unrelated template/runtime configuration.

Local validation: run `npx --yes --package=https://codeload.github.com/Hearmeman24/comfyui-qwen-template/tar.gz/066a32758d4f883bc068656c27fd3a486649eacd catalog-check --root . --base-ref "$(git rev-parse origin/master)"`. CI uses this exact pinned contract.
