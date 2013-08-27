require 'xcodeproj/project/object/helpers/groupable_helper'
require 'xcodeproj/project/object/helpers/file_references_factory'

module Xcodeproj
  class Project
    module Object

      # This class represents a group. A group can contain other groups
      # (PBXGroup) and file references (PBXFileReference).
      #
      class PBXGroup < AbstractObject

        # @!group Attributes

        # @return [ObjectList<PBXGroup, PBXFileReference>]
        #         the objects contained by the group.
        #
        has_many :children, [PBXGroup, PBXFileReference, PBXReferenceProxy]

        # @return [String] the directory to which the path is relative.
        #
        # @note   The accepted values are:
        #         - `<absolute>` for absolute paths
        #         - `<group>` for paths relative to the group
        #         - `SOURCE_ROOT` for paths relative to the project
        #         - `DEVELOPER_DIR` for paths relative to the developer
        #           directory.
        #         - `BUILT_PRODUCTS_DIR` for paths relative to the build
        #           products directory.
        #         - `SDKROOT` for paths relative to the SDK directory.
        #
        attribute :source_tree, String, '<group>'

        # @return [String] the path to a folder in the file system.
        #
        # @note   This attribute is present for groups that are linked to a
        #         folder in the file system.
        #
        attribute :path, String

        # @return [String] the name of the group.
        #
        # @note   If path is specified this attribute is not present.
        #
        attribute :name, String

        # @return [String] Whether Xcode should use tabs for text alignment.
        #
        # @example
        #   `1`
        #
        attribute :uses_tabs, String

        # @return [String] The width of the indent.
        #
        # @example
        #   `2`
        #
        attribute :indent_width, String

        # @return [String] The width of the tabs.
        #
        # @example
        #   `2`
        #
        attribute :tab_width, String

        # @return [String] Whether Xcode should wrap lines.
        #
        # @example
        #   `1`
        #
        attribute :wraps_lines, String

        # @return [String] Comments associated with this group.
        #
        # @note   This is apparently no longer used by Xcode.
        #
        attribute :comments, String

        #---------------------------------------------------------------------#

        public

        # @!group Helpers

        # @return [String] the name of the group taking into account the path
        #         or other factors if needed.
        #
        def display_name
          if name
            name
          elsif path
            File.basename(path)
          elsif self.equal?(project.main_group)
            'Main Group'
          end
        end

        # @return [PBXGroup, PBXProject] the parent of the group.
        #
        def parent
          GroupableHelper.parent(self)
        end

        # @return [Pathname] the absolute path of the group resolving the
        # source tree.
        #
        def real_path
          GroupableHelper.real_path(self)
        end

        # @return [Array<PBXFileReference>] the files references in the group
        #         children.
        #
        def files
          children.select { |obj| obj.class == PBXFileReference }
        end

        # @return [Array<PBXGroup>] the groups in the group children.
        #
        def groups
          children.select { |obj| obj.class == PBXGroup }
        end

        # @return [Array<PBXGroup,PBXFileReference,PBXReferenceProxy>] the
        #         recursive children of the group.
        #
        def recursive_children_groups
          result = []
          groups.each do |child|
            result << child
            result.concat(child.recursive_children_groups)
          end
          result
        end

        # @return [Array<XCVersionGroup>] the version groups in the group
        #         children.
        #
        def version_groups
          children.select { |obj| obj.class == XCVersionGroup }
        end

        # Creates a new reference with the given path and adds it to the
        # group. The reference is configured according to the extension
        # of the path.
        #
        # @param  [#to_s] path
        #         The, preferably absolute, path of the reference.
        #
        # @param  [Symbol] source_tree
        #         The source tree key to use to configure the path (@see
        #         GroupableHelper::SOURCE_TREES_BY_KEY).
        #
        # @return [PBXFileReference, XCVersionGroup] The new reference.
        #
        def new_reference(path, source_tree = :group)
          FileReferencesFactory.new_reference(self, path, source_tree)
        end
        alias :new_file :new_reference

        # Creates a file reference to a static library and adds it to the
        # group.
        #
        # @param  [#to_s] product_name
        #         The name of the static library.
        #
        # @return [PBXFileReference] The new file reference.
        #
        def new_static_library(product_name)
          FileReferencesFactory.new_static_library(self, product_name)
        end

        # Creates a file reference to a new bundle.
        #
        # @param  [#to_s] product_name
        #         The name of the bundle.
        #
        # @return [PBXFileReference] The new file reference.
        #
        def new_bundle(product_name)
          FileReferencesFactory.new_bundle(self, product_name)
        end

        # Creates a file reference to a new bundle and adds it to the group.
        #
        # @note   @see new_reference
        #
        # @param  [#to_s] name
        #         the name of the new group.
        #
        # @return [PBXGroup] the new group.
        #
        def new_group(name, path = nil, source_tree = :group)
          group = project.new(PBXGroup)
          children << group
          group.name = name
          if path
            GroupableHelper.set_path_with_source_tree(group, path, source_tree)
          else
            group.source_tree = '<group>'
          end
          group
        end

        # Traverses the children groups and finds the group with the given
        # path, if exists.
        #
        # @see find_subpath
        #
        def [](path)
          find_subpath(path, false)
        end

        # Removes children files and groups under this group.
        #
        def remove_children_recursively
          children.objects.each(&:remove_from_project)
        end

        # Traverses the children groups and finds the children with the given
        # path, optionally, creating any needed group. If the given path is
        # `nil` it returns itself.
        #
        # @param [String] path
        #   a string with the names of the groups separated by a '`/`'.
        #
        # @param [Boolean] should_create
        #   whether the path should be created.
        #
        # @note The path is matched against the {#display_name} of the groups.
        #
        # @example
        #   g = main_group['Frameworks']
        #   g.name #=> 'Frameworks'
        #
        # @return [PBXGroup] the group if found.
        # @return [Nil] if the path could not be found and should create is
        #         false.
        #
        def find_subpath(path, should_create = false)
          return self unless path
          path = path.split('/') unless path.is_a?(Array)
          child_name = path.shift
          child = children.find{ |c| c.display_name == child_name }
          if child.nil?
            if should_create
              child = new_group(child_name)
            else
              return nil
            end
          end
          if path.empty?
            child
          else
            child.find_subpath(path, should_create)
          end
        end

        # Adds an object to the group.
        #
        # @return [ObjectList<AbstractObject>] the children list.
        #
        def <<(child)
          children << child
        end

        # Sorts the children of the group by type and then by name.
        #
        # @note   This is safe to call in an object list because it modifies it
        #         in C in Ruby MRI. In other Ruby implementation it can cause
        #         issues if there is one call to the notification enabled
        #         methods not compensated by the corespondent opposite (loss of
        #         UUIDs and objects from the project).
        #
        # @return [void]
        #
        def sort_by_type!
          children.sort! do |x, y|
            if x.is_a?(PBXGroup) && y.is_a?(PBXFileReference)
              -1
            elsif x.is_a?(PBXFileReference) && y.is_a?(PBXGroup)
              1
            else
              x.display_name <=> y.display_name
            end
          end
        end
      end

      #-----------------------------------------------------------------------#

      # This class is used to gather localized files into one entry.
      #
      class PBXVariantGroup < PBXGroup

        # @!group Attributes

        # @return [String] the file type guessed by Xcode.
        #
        attribute :last_known_file_type, String

      end

      #-----------------------------------------------------------------------#

      # A group that contains multiple files references to the different
      # versions of a resource.
      #
      # Used to contain the different versions of a `xcdatamodel`.
      #
      class XCVersionGroup < PBXGroup

        # @!group Attributes

        # @return [PBXFileReference] the reference to the current version.
        #
        has_one :current_version, PBXFileReference

        # @return [String] the type of the versioned resource.
        #
        attribute :version_group_type, String, 'wrapper.xcdatamodel'

      end

      #-----------------------------------------------------------------------#

    end
  end
end
