#coding:UTF-8
_erbout = +''; _erbout.<< "<div class=\"mx-auto w-full max-w-6xl\">\n  ".freeze
; _erbout.<<(( render FlatPack::PageTitle::Component.new(
    title: "Recording Studio Accessible Demo",
    subtitle: "Demo of how access works",
    variant: :h1
  ) ).to_s); _erbout.<< "\n\n  <div class=\"mt-6\">\n    ".freeze


; _erbout.<<(( render FlatPack::SectionTitle::Component.new(
      title: "Workspaces",
      subtitle: "Root recordables",
      anchor_link: true,
      anchor_id: "workspace-access"
    ) ).to_s); _erbout.<< "\n\n    ".freeze

; _erbout.<<(( render FlatPack::Grid::Component.new(cols: 3, gap: :md, align: :start, class: "mb-6 w-full") do ).to_s); _erbout.<< "\n      ".freeze
;  if @workspace ; _erbout.<< "\n        ".freeze
; _erbout.<<(( render FlatPack::Card::Component.new(style: :default) do |card| ).to_s); _erbout.<< "\n          ".freeze
;  card.body(class: "grid gap-3 justify-items-start") do ; _erbout.<< "\n            <h3 class=\"text-lg font-semibold leading-tight text-slate-900\">".freeze
; _erbout.<<(( @workspace.name ).to_s); _erbout.<< "</h3>\n            ".freeze
; _erbout.<<(( render FlatPack::Badge::Component.new(text: @workspace.class.name, style: :default, size: :sm) ).to_s); _erbout.<< "\n            <p class=\"text-sm text-slate-600\">\n              ".freeze

; _erbout.<<(( pluralize(@workspace_access_rows.count, "person") ).to_s); _erbout.<< " with access\n            </p>\n            ".freeze

;  if @root_recording && @root_access_management_enabled ; _erbout.<< "\n              ".freeze
; _erbout.<<(( render FlatPack::Button::Component.new(
                text: "Change access",
                style: :default,
                size: :sm,
                url: recording_studio_accessible.recording_accesses_path(@root_recording)
              ) ).to_s); _erbout.<< "\n            ".freeze
;  end ; _erbout.<< "\n          ".freeze
;  end ; _erbout.<< "\n        ".freeze
;  end ; _erbout.<< "\n      ".freeze
;  end ; _erbout.<< "\n    ".freeze
;  end ; _erbout.<< "\n\n    ".freeze

; _erbout.<<(( render FlatPack::SectionTitle::Component.new(
      title: "Folders and pages",
      anchor_link: true,
      anchor_id: "folders-and-pages"
    ) ).to_s); _erbout.<< "\n\n    ".freeze

; _erbout.<<(( render FlatPack::Grid::Component.new(cols: 3, gap: :md, align: :start, class: "w-full") do ).to_s); _erbout.<< "\n      ".freeze
;  @demo_sections.each do |section| ; _erbout.<< "\n        ".freeze
; _erbout.<<(( render FlatPack::Card::Component.new(style: :default) do |card| ).to_s); _erbout.<< "\n          ".freeze
;  card.body(class: "grid gap-3 justify-items-start") do ; _erbout.<< "\n            <h3 class=\"text-lg font-semibold leading-tight text-slate-900\">".freeze
; _erbout.<<(( section[:folder].name ).to_s); _erbout.<< "</h3>\n            ".freeze
;  folder_direct_access_count = @direct_access_counts_by_recording_id.fetch(section[:folder_recording]&.id, 0) ; _erbout.<< "\n            ".freeze
; _erbout.<<(( render FlatPack::Badge::Component.new(text: section[:folder].class.name, style: :default, size: :sm) ).to_s); _erbout.<< "\n            <p class=\"text-sm text-slate-600\">".freeze
; _erbout.<<(( folder_direct_access_count ).to_s); _erbout.<< " access</p>\n            ".freeze
;  if section[:folder_recording] && section[:folder_access_management_enabled] ; _erbout.<< "\n              ".freeze
; _erbout.<<(( render FlatPack::Button::Component.new(
                text: "Change access",
                style: :default,
                size: :sm,
                url: recording_studio_accessible.recording_accesses_path(section[:folder_recording])
              ) ).to_s); _erbout.<< "\n            ".freeze
;  end ; _erbout.<< "\n          ".freeze
;  end ; _erbout.<< "\n        ".freeze
;  end ; _erbout.<< "\n\n        ".freeze

;  section[:pages].each do |page_section| ; _erbout.<< "\n          ".freeze
; _erbout.<<(( render FlatPack::Card::Component.new(style: :outlined) do |card| ).to_s); _erbout.<< "\n            ".freeze
;  card.body(class: "grid gap-3 justify-items-start") do ; _erbout.<< "\n              <h3 class=\"text-lg font-semibold leading-tight text-slate-900\">".freeze
; _erbout.<<(( page_section[:page].title ).to_s); _erbout.<< "</h3>\n              ".freeze
;  page_direct_access_count = @direct_access_counts_by_recording_id.fetch(page_section[:page_recording]&.id, 0) ; _erbout.<< "\n              ".freeze
; _erbout.<<(( render FlatPack::Badge::Component.new(text: page_section[:page].class.name, style: :default, size: :sm) ).to_s); _erbout.<< "\n              <p class=\"text-sm text-slate-600\">".freeze
; _erbout.<<(( page_direct_access_count ).to_s); _erbout.<< " access</p>\n              <p class=\"text-sm text-slate-600\">Pages not allowed to add access</p>\n              ".freeze

;  if page_section[:page_recording] && page_section[:page_access_management_enabled] ; _erbout.<< "\n                ".freeze
; _erbout.<<(( render FlatPack::Button::Component.new(
                  text: "Change access",
                  style: :default,
                  size: :sm,
                  url: recording_studio_accessible.recording_accesses_path(page_section[:page_recording])
                ) ).to_s); _erbout.<< "\n              ".freeze
;  end ; _erbout.<< "\n            ".freeze
;  end ; _erbout.<< "\n          ".freeze
;  end ; _erbout.<< "\n        ".freeze
;  end ; _erbout.<< "\n      ".freeze
;  end ; _erbout.<< "\n    ".freeze
;  end ; _erbout.<< "\n  </div>\n</div>\n".freeze


; _erbout
