require 'hammer_cli_katello/content_view_puppet_module'
require 'hammer_cli_katello/content_view_purge'
require 'hammer_cli_katello/filter'
require 'hammer_cli_katello/content_view_version'
require 'hammer_cli_katello/content_view_component'

module HammerCLIKatello
  class ContentView < HammerCLIKatello::Command
    resource :content_views

    class ListCommand < HammerCLIKatello::ListCommand
      include KatelloEnvironmentNameResolvable
      output do
        field :id, _("Content View ID")
        field :name, _("Name")
        field :label, _("Label")
        field :composite, _("Composite")
        field :last_published, _("Last Published"), Fields::Date, :hide_blank => true
        field :repository_ids, _("Repository IDs"), Fields::List
      end

      build_options
    end

    class InfoCommand < HammerCLIKatello::InfoCommand
      include OrganizationOptions

      output do
        field :id, _("ID")
        field :name, _("Name")
        field :label, _("Label")
        field :composite, _("Composite")
        field :description, _("Description")
        field :content_host_count, _("Content Host Count")

        from :organization do
          field :name, _("Organization")
        end

        collection :_yum_repositories, _("Yum Repositories") do
          field :id, _("ID")
          field :name, _("Name")
          field :label, _("Label")
        end

        collection :_docker_repositories, _("Docker Repositories") do
          field :id, _("ID")
          field :name, _("Name")
          field :label, _("Label")
        end

        collection :_ostree_repositories, _("OSTree Repositories") do
          field :id, _("ID")
          field :name, _("Name")
          field :label, _("Label")
        end

        collection :puppet_modules, _("Puppet Modules") do
          field :id, _("ID")
          field :uuid, _("UUID"), Fields::Field, :hide_blank => true
          field :name, _("Name")
          field :author, _("Author")
        end

        collection :environments, _("Lifecycle Environments") do
          field :id, _("ID")
          field :name, _("Name")
        end

        collection :versions, _("Versions") do
          field :id, _("ID")
          field :version, _("Version")
          field :published, _("Published"), Fields::Date
        end

        collection :components, _("Components") do
          field :id, _("ID")
          field :name, _("Name")
        end

        collection :activation_keys, _("Activation Keys") do
          custom_field Fields::Reference
        end
      end

      def extend_data(data)
        %w(yum docker ostree).each do |content_type|
          data["_#{content_type}_repositories"] = data["repositories"].select do |repo|
            repo["content_type"] == content_type
          end
        end

        data
      end

      build_options
    end

    class CreateCommand < HammerCLIKatello::CreateCommand
      success_message _("Content view created")
      failure_message _("Could not create the content view")

      option ["--composite"], :flag, _("Create a composite content view")

      def request_params
        super.tap do |opts|
          opts['composite'] = option_composite? || false
        end
      end

      validate_options do
        product_options = [:option_product_id, :option_product_name]
        if option(:option_repository_ids).exist?
          any(*product_options).rejected
          option(:option_repository_names).rejected
        end

        if option(:option_repository_names).exist?
          any(*product_options).required
        end
      end

      build_options do |o|
        o.expand.including(:products)
      end
    end

    class CopyCommand < HammerCLIKatello::CreateCommand
      include OrganizationOptions

      action :copy

      desc _("Copy a content view")
      command_name "copy"

      option "--name", "NAME", _("Content view name to search by"), :attribute_name => :option_name
      option "--new-name", "NEW_NAME", _("New content view name"),
             :attribute_name => :option_new_name

      validate_options do
        organization_options = [:option_organization_id, :option_organization_name, \
                                :option_organization_label]

        if option(:option_name).exist?
          any(*organization_options).required
        end
      end

      def request_params
        super.tap do |opts|
          opts['name'] = option_new_name
        end
      end

      build_options

      success_message _("Content view copied")
      failure_message _("Could not copy the content view")
    end

    class UpdateCommand < HammerCLIKatello::UpdateCommand
      include OrganizationOptions

      success_message _("Content view updated")
      failure_message _("Could not update the content view")

      validate_options do
        organization_options = [:option_organization_id, :option_organization_name, \
                                :option_organization_label]

        if option(:option_name).exist?
          any(*organization_options).required
        end
      end

      build_options
    end

    class DeleteCommand < HammerCLIKatello::DeleteCommand
      include HammerCLIForemanTasks::Async
      include OrganizationOptions

      action :destroy
      command_name "delete"

      success_message _("Content view is being deleted with task %{id}")
      failure_message _("Could not delete the content view")

      validate_options do
        organization_options = [:option_organization_id, :option_organization_name, \
                                :option_organization_label]

        if option(:option_name).exist?
          any(*organization_options).required
        end
      end

      build_options
    end

    class PublishCommand < HammerCLIKatello::SingleResourceCommand
      include HammerCLIForemanTasks::Async
      include OrganizationOptions

      action :publish
      command_name "publish"

      success_message _("Content view is being published with task %{id}")
      failure_message _("Could not publish the content view")

      build_options
    end

    class RemoveFromEnvironmentCommand < HammerCLIKatello::SingleResourceCommand
      include KatelloEnvironmentNameResolvable
      include HammerCLIForemanTasks::Async
      include OrganizationOptions

      action :remove_from_environment
      command_name "remove-from-environment"

      success_message _("Content view is being removed from environment with task %{id}")
      failure_message _("Could not remove the content view from environment")

      build_options
    end

    class CVEnvParamsSource
      def initialize(command)
        @command = command
      end

      def get_options(_defined_options, result)
        result['option_content_view_id'] = @command.option_id
        result['option_lifecycle_environment_names'] = result['option_environment_names']
        result
      end
    end

    class RemoveCommand < HammerCLIKatello::SingleResourceCommand
      include HammerCLIForemanTasks::Async
      include OrganizationOptions

      # command to remove content view environments and versions from a content view.
      # corresponds to the UI screen.
      action :remove
      command_name "remove"

      option ["--content-view-version-ids"], "VERSION_IDS",
             _("Version ids to remove"),
            :format => HammerCLI::Options::Normalizers::List.new
      option ["--environment-ids"], "ENVIRONMENT_IDS",
             _("Environment ids to remove"),
            :format => HammerCLI::Options::Normalizers::List.new

      def option_sources
        sources = super
        idx = sources.index { |s| s.class == HammerCLIForeman::OptionSources::IdParams }
        sources.insert(idx, CVEnvParamsSource.new(self))
        sources
      end

      def request_params
        super.tap do |opts|
          %w(content_view_version_ids environment_ids).each do |key|
            opts[key] = opts[key].split(",") if opts[key] && opts[key].respond_to?(:split)
          end
        end
      end

      success_message _("Content view objects are being removed task %{id}")
      failure_message _("Could not remove objects from content view")

      build_options
    end

    class AddContentViewVersionCommand < HammerCLIKatello::AddAssociatedCommand
      include OrganizationOptions

      command_name 'add-version'
      desc _('Add a content view version to a composite view')

      validate_options do
        if option(:option_content_view_version_version).exist?
          any(:option_content_view_id, :option_content_view_name).required
        end
      end

      def association_name(plural = false)
        plural ? "components" : "component"
      end

      validate_options do
        organization_options = [:option_organization_id, :option_organization_name, \
                                :option_organization_label]

        if option(:option_name).exist?
          any(*organization_options).required
        end
      end

      associated_resource :content_view_versions

      build_options do |o|
        o.expand.including(:content_views)
      end

      success_message _("The component version has been added")
      failure_message _("Could not add version")
    end

    class RemoveContentViewVersionCommand < HammerCLIKatello::RemoveAssociatedCommand
      include OrganizationOptions

      command_name 'remove-version'
      desc _('Remove a content view version from a composite view')

      validate_options do
        if option(:option_content_view_version_version).exist?
          any(:option_content_view_id, :option_content_view_name).required
        end
      end

      def association_name(plural = false)
        plural ? "components" : "component"
      end

      validate_options do
        organization_options = [:option_organization_id, :option_organization_name, \
                                :option_organization_label]

        if option(:option_name).exist?
          any(*organization_options).required
        end
      end

      associated_resource :content_view_versions

      build_options do |o|
        o.expand.including(:content_views)
      end

      success_message _("The component version has been removed")
      failure_message _("Could not remove version")
    end

    HammerCLIKatello::AssociatingCommands::Repository.extend_command(self)

    autoload_subcommands

    subcommand 'puppet-module',
               HammerCLIKatello::ContentViewPuppetModule.desc,
               HammerCLIKatello::ContentViewPuppetModule

    subcommand HammerCLIKatello::Filter.command_name,
               HammerCLIKatello::Filter.desc,
               HammerCLIKatello::Filter

    subcommand HammerCLIKatello::ContentViewVersion.command_name,
               HammerCLIKatello::ContentViewVersion.desc,
               HammerCLIKatello::ContentViewVersion

    subcommand HammerCLIKatello::ContentViewComponent.command_name,
               HammerCLIKatello::ContentViewComponent.desc,
               HammerCLIKatello::ContentViewComponent

    subcommand HammerCLIKatello::ContentViewPurgeCommand.command_name,
               HammerCLIKatello::ContentViewPurgeCommand.desc,
               HammerCLIKatello::ContentViewPurgeCommand
  end
end
