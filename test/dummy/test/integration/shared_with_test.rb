# frozen_string_literal: true

require_relative "../test_helper"

class SharedWithScreenTest < ActionDispatch::IntegrationTest
  setup do
    @configuration = RecordingStudioAccessible.configuration
    @original_resolver = @configuration.shared_item_resolver
    @owner = create_user("shared-screen-owner-#{SecureRandom.hex(4)}@example.com")
    Current.actor = @owner
    @person = create_user("shared-screen-person-#{SecureRandom.hex(4)}@example.com")
    @outsider = create_user("shared-screen-outsider-#{SecureRandom.hex(4)}@example.com")
    @workspace = Workspace.create!(name: "Screen Workspace #{SecureRandom.hex(4)}")
    @root = create_root_recording(@workspace)
    create_direct_access_recording(actor: @owner, role: :admin, parent_recording: @root)
    @folder = Folder.create!(workspace: @workspace, name: "Press kit #{SecureRandom.hex(4)}", summary: "Kit", position: 0)
    @recording = create_child_recording(recordable: @folder, parent_recording: @root)
    create_direct_access_recording(actor: @person, role: :edit, parent_recording: @recording)
  end

  teardown do
    @configuration.shared_item_resolver = @original_resolver
    @configuration.access_management_current_actor_resolver = @configuration.method(:default_access_management_current_actor_resolver)
    Current.actor = nil
  end

  test "a signed-in person sees the shared item and an empty list stays empty" do
    sign_in @person

    get recording_studio_accessible.shared_with_path

    assert_response :success
    assert_select "turbo-frame#shared_with_index"
    assert_match "Shared with me", response.body
    assert_match "Everything shared with you, one by one.", response.body
    assert_select "table", count: 0
    assert_select ".fp-card.border ul.flat-pack-list-divided[data-pagination-content]"
    assert_shared_row(@folder.name, @workspace.name, main_workspace_path, hidden_role: "Edit")

    sign_in @outsider
    get recording_studio_accessible.shared_with_path

    assert_response :success
    assert_match "Nothing here yet", response.body
    assert_match "When someone shares something with you, it shows up here.", response.body
    refute_match @folder.name, response.body
    assert_select ".fp-card", count: 0
  end

  test "a signed-out visit redirects and a blank actor is forbidden" do
    get recording_studio_accessible.shared_with_path

    assert_redirected_to "/users/sign_in"

    sign_in @person
    @configuration.access_management_current_actor_resolver = ->(**) { nil }

    get recording_studio_accessible.shared_with_path

    assert_response :forbidden
  end

  test "the resolver chooses the link and a bad cursor is rejected" do
    hidden = Folder.create!(workspace: @workspace, name: "Secret notes #{SecureRandom.hex(4)}", summary: "Hidden", position: 1)
    hidden_recording = create_child_recording(recordable: hidden, parent_recording: @root)
    create_direct_access_recording(actor: @person, role: :view, parent_recording: hidden_recording)
    @configuration.shared_item_resolver = lambda do |recording|
      next if recording.recordable == hidden

      { title: recording.recordable.name, url: "/kits/#{recording.id}" }
    end
    sign_in @person

    get recording_studio_accessible.shared_with_path

    assert_response :success
    assert_shared_row(@folder.name, @workspace.name, "/kits/#{@recording.id}", hidden_role: "Edit")
    refute_match hidden.name, response.body
    refute_match "polymorphic", response.body

    get recording_studio_accessible.shared_with_path(cursor: "nope")

    assert_response :bad_request
  end

  test "another page keeps a cursor on the last row" do
    10.times do |index|
      folder = Folder.create!(
        workspace: @workspace,
        name: "Extra kit #{index} #{SecureRandom.hex(2)}",
        summary: "Kit",
        position: index + 1
      )
      recording = create_child_recording(recordable: folder, parent_recording: @root)
      create_direct_access_recording(actor: @person, role: :view, parent_recording: recording)
    end
    sign_in @person

    get recording_studio_accessible.shared_with_path

    assert_response :success
    assert_select "ul[data-pagination-content] li", count: RecordingStudioAccessible::SharedWith::PAGE_SIZE
    assert_select "li:last-child [data-pagination-cursor]"
    assert_select "[data-flat-pack--pagination-infinite-loading-variant-value=?]", "inline"
    assert_select "[data-flat-pack--pagination-infinite-cursor-selector-value=?]",
                  "li:last-child [data-pagination-cursor]"
  end

  test "an unset resolver hides every row" do
    @configuration.shared_item_resolver = nil
    sign_in @person

    get recording_studio_accessible.shared_with_path

    assert_response :success
    assert_match "Nothing here yet", response.body
    assert_match "When someone shares something with you, it shows up here.", response.body
    refute_match @folder.name, response.body
  end

  private

  def create_user(email)
    User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def main_workspace_path
    Rails.application.routes.url_helpers.workspace_path(@workspace)
  end

  def assert_shared_row(title, workspace, href, hidden_role:)
    assert_select "li" do |rows|
      row = rows.find { |candidate| candidate.at("a")&.text&.squish == title }
      assert row, "expected a row for #{title}"
      assert_equal href, row.at("a")["href"]
      assert_includes row.at("a")["class"].to_s, "underline"
      detail = row.at(".fp-list-item-subtitle")
      assert_equal workspace, detail.text.squish
      refute_includes detail.text, hidden_role
      assert row.at("[data-pagination-cursor]")
    end
  end
end
