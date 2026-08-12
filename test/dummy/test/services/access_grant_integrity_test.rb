require_relative "../test_helper"
require "rake"

class AccessGrantIntegrityTest < ActiveSupport::TestCase
  class PartiallyFailingAccessGrantIntegrity < RecordingStudioAccessible::Services::AccessGrantIntegrity
    attr_accessor :failing_parent_recording_id, :forced_groups

    private

    def duplicate_groups
      forced_groups || super
    end

    def destroy_access_recording!(access_recording, manager_actor:)
      if access_recording.parent_recording_id == failing_parent_recording_id
        raise "simulated lifecycle failure"
      end

      super
    end
  end

  setup do
    @manager = create_user("integrity-manager@example.com")
    @actor = create_user("integrity-actor@example.com")
    workspace = Workspace.create!(name: "Integrity Workspace")
    @root_recording = create_root_recording(workspace)
    folder = Folder.create!(workspace: workspace, name: "Integrity Folder", summary: "Folder", position: 0)
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @root_recording)
  end

  test "dry run reports duplicate groups without changing records" do
    older, newer = malformed_duplicate_pair(parent: @root_recording, roles: %i[admin view])

    result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call

    assert result.success?
    report = result.value.fetch(:report).sole
    assert_equal [ newer.id, older.id ], report[:access_recording_ids]
    assert_equal "admin", report[:strongest_role]
    assert_equal newer.id, report[:retained_access_recording_id]
    assert_equal :would_repair, report[:status]
    assert_equal 2, active_grants_for(@actor, @root_recording).count
  end

  test "repair retains the newest recording, promotes its role, and removes redundant pairs" do
    older, newer = malformed_duplicate_pair(parent: @root_recording, roles: %i[admin view])

    result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)

    assert result.success?
    report = result.value.fetch(:report).sole
    assert_equal :repaired, report[:status]
    assert_equal newer.id, report[:retained_access_recording_id]
    assert_equal [ newer.id ], active_grants_for(@actor, @root_recording).pluck(:id)
    assert_equal "admin", newer.reload.recordable.role
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: older.id)
    assert_nil RecordingStudio::Access.find_by(id: older.recordable_id)
    assert_equal @manager.id, RecordingStudio::Event.where(action: "deleted").order(:created_at, :id).last.actor_id
  end

  test "repair is idempotent and never combines grants under distinct parents or actors" do
    malformed_duplicate_pair(parent: @root_recording, roles: %i[view edit])
    malformed_duplicate_pair(parent: @folder_recording, roles: %i[admin view])
    other_actor = create_user("integrity-other@example.com")
    create_direct_access_recording(actor: other_actor, role: :view, parent_recording: @root_recording)

    first = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)
    second = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)

    assert first.success?
    assert second.success?
    assert_equal 1, active_grants_for(@actor, @root_recording).count
    assert_equal 1, active_grants_for(@actor, @folder_recording).count
    assert_equal 1, active_grants_for(other_actor, @root_recording).count
    assert_empty second.value.fetch(:report)
  end

  test "repair requires an explicit manager and leaves groups with no valid role untouched" do
    malformed_duplicate_pair(parent: @root_recording, roles: [ 99, 98 ])

    missing_manager = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false)
    repair = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)

    assert missing_manager.failure?
  assert_equal "A persisted manager actor with a GlobalID is required for repair", missing_manager.error
    assert repair.success?
    assert_equal :skipped_no_valid_role, repair.value.fetch(:report).sole[:status]
    assert_equal 2, active_grants_for(@actor, @root_recording).count
  end

  test "repair rejects managers that cannot be used for audit attribution before modifying grants" do
    malformed_duplicate_pair(parent: @root_recording, roles: %i[view admin])
    unsaved_manager = User.new(email: "unsaved-integrity-manager@example.com", password: "Password",
                               password_confirmation: "Password")
    unsaved_manager.id = SecureRandom.uuid
    arbitrary_manager = Struct.new(:id).new(SecureRandom.uuid)

    [ nil, unsaved_manager, arbitrary_manager ].each do |manager|
      result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: manager)

      assert result.failure?
      assert_equal "A persisted manager actor with a GlobalID is required for repair", result.error
      assert_equal 2, active_grants_for(@actor, @root_recording).count
    end
  end

  test "repair preserves the complete report when a later parent group fails" do
    malformed_duplicate_pair(parent: @root_recording, roles: %i[view admin])
    malformed_duplicate_pair(parent: @folder_recording, roles: %i[admin view])
    service = PartiallyFailingAccessGrantIntegrity.new(dry_run: false, manager_actor: @manager)
    service.failing_parent_recording_id = @root_recording.id
    groups = service.send(:duplicate_groups).sort_by do |group|
      group[:parent_recording_id] == @folder_recording.id ? 0 : 1
    end
    service.forced_groups = groups

    result = service.call

    assert result.failure?
    assert_equal "Some duplicate access grants could not be repaired", result.error
    report = result.value.fetch(:report)
    assert_equal %i[repaired failed], report.map { |entry| entry[:status] }
    assert_equal @folder_recording.id, report.first[:parent_recording_id]
    assert_equal @root_recording.id, report.second[:parent_recording_id]
    assert_equal 1, active_grants_for(@actor, @folder_recording).count
    assert_equal 2, active_grants_for(@actor, @root_recording).count
  end

  test "repair prepares the Current impersonator accessor before lifecycle mutations" do
    malformed_duplicate_pair(parent: @root_recording, roles: %i[view admin])
    original_current = Object.const_get(:Current)
    Object.send(:remove_const, :Current)
    replacement_current = Class.new(ActiveSupport::CurrentAttributes) { attribute :actor }
    Object.const_set(:Current, replacement_current)

    result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)

    assert result.success?
    assert replacement_current.respond_to?(:impersonator)
  ensure
    Object.send(:remove_const, :Current) if Object.const_defined?(:Current, false)
    Object.const_set(:Current, original_current) if original_current
  end

  test "integrity task prints complete partial-failure reports before aborting" do
    task_name = "recording_studio_accessible:access_grants:integrity"
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load RecordingStudioAccessible::Engine.root.join("lib/tasks/recording_studio_accessible.rake") unless Rake::Task.task_defined?(task_name)
    Rake::Task[task_name].reenable
    report = [
      { parent_recording_id: @folder_recording.id, status: :repaired },
      { parent_recording_id: @root_recording.id, status: :failed, error: "simulated lifecycle failure" }
    ]
    result = RecordingStudioAccessible::Services::BaseService::Result.new(
      success: false,
      value: { report: report, dry_run: false },
      error: "Some duplicate access grants could not be repaired",
      errors: [ report.last ]
    )
    service_class = RecordingStudioAccessible::Services::AccessGrantIntegrity
    service_class.singleton_class.alias_method(:call_before_task_test, :call)
    service_class.define_singleton_method(:call) { |*_, **_| result }

    stdout, stderr = capture_io do
      assert_raises(SystemExit) { Rake::Task[task_name].invoke }
    end

    assert_includes stdout, @folder_recording.id
    assert_includes stdout, ":repaired"
    assert_includes stdout, @root_recording.id
    assert_includes stdout, ":failed"
    assert_includes stderr, "Some duplicate access grants could not be repaired"
  ensure
    if defined?(service_class) && service_class.singleton_class.method_defined?(:call_before_task_test)
      service_class.singleton_class.alias_method(:call, :call_before_task_test)
      service_class.singleton_class.remove_method(:call_before_task_test)
    end
    Rake::Task[task_name]&.reenable if defined?(task_name)
  end

  test "repair normalizes legacy STI actor types before grouping and retaining a grant" do
    first, second = malformed_duplicate_pair(parent: @root_recording, roles: %i[view admin])
    Object.const_set("IntegritySpecialUser", Class.new(User))
    mutate_access!(second, actor_type: "IntegritySpecialUser")

    result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(dry_run: false, manager_actor: @manager)

    assert result.success?
    assert_equal [ second.id, first.id ], result.value.fetch(:report).sole[:access_recording_ids]
    assert_equal "User", second.reload.recordable.actor_type
  ensure
    Object.send(:remove_const, "IntegritySpecialUser") if Object.const_defined?("IntegritySpecialUser", false)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def malformed_duplicate_pair(parent:, roles:)
    first = create_direct_access_recording(actor: @actor, role: seed_role(roles.first), parent_recording: parent)
    second = create_direct_access_recording(actor: create_user("integrity-duplicate-#{parent.id}-#{roles.last}@example.com"),
                                            role: seed_role(roles.last), parent_recording: parent)
    mutate_access!(first, role: roles.first)
    mutate_access!(second, actor: @actor, role: roles.last)
    [ first, second ]
  end

  def mutate_access!(access_recording, actor: nil, actor_type: nil, role: nil)
    connection = ActiveRecord::Base.connection
    assignments = []
    assignments << "actor_type = #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))}" if actor
    assignments << "actor_id = #{connection.quote(actor.id)}" if actor
    assignments << "actor_type = #{connection.quote(actor_type)}" if actor_type
    assignments << "role = #{connection.quote(stored_role(role))}" unless role.nil?
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses SET #{assignments.join(', ')}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def seed_role(role)
    role.is_a?(Integer) ? :view : role
  end

  def stored_role(role)
    RecordingStudio::Access.roles.fetch(role.to_s, role)
  end

  def active_grants_for(actor, parent)
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: parent, actor: actor)
  end
end