---
description: "Use when editing ERB views, layout partials, or UI-facing Rails templates. Covers FlatPack-first UI decisions for this repository, with an emphasis on standardized and testable ViewComponents over custom HTML or JavaScript."
applyTo: ["app/views/**/*.erb", "test/dummy/app/views/**/*.erb"]
---

# View Guidelines

- Prefer `render FlatPack::...` components over custom HTML whenever an equivalent component exists.
- Prefer standardized, testable FlatPack ViewComponents over one-off ERB structures or custom JavaScript behaviors.
- Keep raw HTML limited to simple semantic wrappers, prose, or content that FlatPack does not cover.
- Preserve the existing FlatPack visual language in the dummy app and engine views.
- When introducing custom markup, keep it minimal and avoid building ad hoc reusable controls in ERB.
- Do not add custom JavaScript for UI behavior until you have confirmed FlatPack or the existing Rails/Hotwire stack does not already provide the needed interaction.