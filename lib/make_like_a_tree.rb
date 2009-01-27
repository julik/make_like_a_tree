module Julik
  module MakeLikeTree
    class ImpossibleReparent < RuntimeError
    end
    
    VERSION = '1.0.3'
    def self.included(base) #:nodoc:
      super
      base.extend(ClassMethods)
    end
      
    # Injects the module into ActiveRecord
    def self.bootstrap!
      ::ActiveRecord::Base.send :include, self
    end
      
    module ClassMethods
      # An acts_as_threaded on steroids. Configuration options are:
      #
      # * +root_column+ - specifies the column name to use for identifying the root thread, default "root_id"
      # * +parent_column+ - specifies the column name to use for keeping the position integer, default "parent_id"
      # * +left_column+ - column name for left boundary data, default "lft"
      # * +right_column+ - column name for right boundary data, default "rgt"
      # * +depth+ - column name used to track the depth in the branch, default "depth"
      # * +scope+ - adds an additional contraint on the threads when searching or updating
      def make_like_a_tree(options = {})
        configuration = { :root_column => "root_id", :parent_column => "parent_id", :left_column => "lft", :right_column => "rgt", :depth_column => 'depth', :scope => "(1=1)" }
        configuration.update(options) if options.is_a?(Hash)
        configuration[:scope] = "#{configuration[:scope]}_id".intern if configuration[:scope].is_a?(Symbol) && configuration[:scope].to_s !~ /_id$/

        if configuration[:scope].is_a?(Symbol)
          scope_condition_method = %(
            def scope_condition
              if #{configuration[:scope].to_s}.nil?
                "#{configuration[:scope].to_s} IS NULL"
              else
                "#{configuration[:scope].to_s} = \#{#{configuration[:scope].to_s}}"
              end
            end
          )
        else
          scope_condition_method = "def scope_condition() \"#{configuration[:scope]}\" end"
        end
        
        after_create :apply_parenting_after_create
        
        
       # before_update :register_parent_id_before_update, :unless => :new_record?
      #  after_update :replant_after_update
        
        # TODO: refactor for class << self
        class_eval <<-EOV
          include Julik::MakeLikeTree::InstanceMethods

          #{scope_condition_method}

          def root_column() "#{configuration[:root_column]}" end
          def parent_column() "#{configuration[:parent_column]}" end
          def left_col_name() "#{configuration[:left_column]}" end
          def right_col_name() "#{configuration[:right_column]}" end
          def depth_column() "#{configuration[:depth_column]}" end

        EOV
      end
    end

    module InstanceMethods
      
      # Move the item to a specific index within the range of it's siblings. Used to reorder lists.
      # Will cause a cascading update on the neighbouring items and their children, but the update will be scoped
      def move_to(idx)
        transaction do 
          # Take a few shortcuts to avoid extra work
          cur_idx = index_in_parent
          return true if (cur_idx == idx)
        
          range = siblings_and_self
          return true if range.length == 1
        
          cur_idx = range.index(self)
          return true if cur_idx == idx
        
          # Register starting and ending elements
          start_left, end_right = range[0][left_col_name], range[-1][right_col_name]
        
          old_range = range.dup
        
          range.delete_at(cur_idx)
          range.insert(idx, self)
          range.compact! # If we inserted something outside of range and created empty slots
        
          # Now remap segements
          left_remaps, right_remaps = [], []
        
          # Exhaust the range starting with the last element, determining a remap on the fly
          while range.any?
            e = range.pop
          
            w = (e[right_col_name] - e[left_col_name])

            # Determine by how many we need to shift the adjacent keys to put this item into place
            offset_in_range = range.inject(0) do | sum, item_before |
              sum + item_before[right_col_name] - item_before[left_col_name] + 1
            end
            shift = offset_in_range - e[left_col_name] + 1
            
            unless shift.zero? # Optimize - do not move nodes that stay in the same place
              condition_stmt = "#{left_col_name} >= #{e[left_col_name]} AND #{right_col_name} <= #{e[right_col_name]}"
          
              left_remaps.unshift(
                "WHEN (#{condition_stmt}) THEN (#{left_col_name} + #{shift})"
              )
              right_remaps.unshift(
                "WHEN (#{condition_stmt}) THEN (#{right_col_name} + #{shift})"
              )
            end
          end
        
          # If we are not a root node, scope the changes to our subtree only - this will win us some less writes
          update_condition = root? ? scope_condition : "#{scope_condition} AND #{root_column} = #{self[root_column]}"
          
          self.class.update_all(
            "#{left_col_name} = CASE #{left_remaps.join(' ')} ELSE #{left_col_name} END, " + 
            "#{right_col_name} = CASE #{right_remaps.join(' ')} ELSE #{right_col_name} END ",
            update_condition
          )
        end
      end

      # Move the record down in the list (uses move_to)
      def move_up
        move_to(index_in_parent - 1)
      end
      
      # Move the record up in the list (uses move_to)
      def move_down
        move_to(index_in_parent + 1)
      end
      
      # Move the record to top of the list (uses move_to)
      def move_to_top
        move_to(0)
      end
      
      # Move the record to the bottom of the list (uses move_to)
      def move_to_bottom
        move_to(-1)
      end
      
      # Get the item index in parent. TODO: when the tree is balanced with no orphan counts, just use (rgt-lft)/2
      def index_in_parent
        # Fetch the item count of items that have the same root_id and the same parent_id and are lower than me on the indices
        @index_in_parent ||= self.class.count_by_sql(
          "SELECT COUNT(id) FROM #{self.class.table_name} WHERE " + 
          "#{right_col_name} < #{self[left_col_name]} AND  #{parent_column} = #{self[parent_column]}"
        )
      end
      
      # Override ActiveRecord::Base#reload to blow over all the memoized values
      def reload(*any_arguments)
        @index_in_parent, @is_root, @is_child, @old_parent_id, @rerooted = nil, nil, nil, nil, nil
        super
      end
      
      # Returns true is this is a root thread.
      def root?
        @is_root ||= (self[root_column].to_i.zero? ||  (self[root_column] == self.id))
      end

      # Returns true is this is a child node
      def child?
        parent_id = self[parent_column]
        @is_child ||= (!(parent_id.to_i.zero?) && (self[left_col_name] > 1) && (self[right_col_name] > self[left_col_name]))
      end

      # Returns true if we have no idea what this is
      def unknown?
        !root? && !child?
      end
      
      # Used as an after_create callback to apply the parent_id assignment or create a root node
      def apply_parenting_after_create
        reload # Reload to bring in the id
        assign_default_left_and_right
        self.save
        unless self[parent_column].to_i.zero?
          # Load the parent
          parent = self.class.find(self[parent_column])
          parent.add_child self
        end
        true
      end
      
      # Place the item to the appropriate place as a root item
      def assign_default_left_and_right(with_space_inside = 0)
        
        # Instead of creating nodes with 0,0 make this a root node BY DEFAULT even if no children are specified
        self[root_column] = self.id
        last_root_node = self.class.find(:first, :conditions => "#{scope_condition} AND #{parent_column} = 0 AND id != #{self.id}",
          :order => "#{right_col_name} DESC", :limit => 1)
        offset = last_root_node ? last_root_node[right_col_name] : 0
        
        self[left_col_name], self[right_col_name] = (offset+1), (offset + with_space_inside + 2)
      end
      
      # Shortcut for self[depth_column]
      def level
        self[depth_column]
      end
      
      # Adds a child to this object in the tree.  If this object hasn't been initialized,
      # it gets set up as a root node.  Otherwise, this method will update all of the
      # other elements in the tree and shift them to the right, keeping everything
      # balanced.
      def add_child(child)
        begin
          add_child!(child)
        rescue ImpossibleReparent
          false
        end
      end
      
      # Tells you if a reparent might be invalid
      def child_can_be_added?(child)
        impossible = (child[root_column] == self[root_column] && 
          child[left_col_name] < self[left_col_name]) && 
          (child[right_col_name] > self[right_col_name])
        !impossible
      end
      
      # A noisy version of add_child, will raise an ImpossibleReparent if you try to reparent a node onto its indirect child
      def add_child!(child)
        raise ImpossibleReparent, "Cannot reparent #{child} onto its child node #{self}" unless child_can_be_added?(child)

        k = self.class
        
        new_left, new_right = determine_range_for_child(child)
        
        move_by = new_left - child[left_col_name]
        move_depth_by = (self[depth_column] + 1) - child[depth_column]
        
        child_occupies = (new_right - new_left) + 1
        
        transaction do
          # bring the child and its grandchildren over
          self.class.update_all( 
            "#{depth_column} = #{depth_column} + #{move_depth_by}," +
            "#{root_column} = #{self[root_column]}," +
            "#{left_col_name} = #{left_col_name} + #{move_by}," +
            "#{right_col_name} = #{right_col_name} + #{move_by}",
            "#{scope_condition} AND #{left_col_name} >= #{child[left_col_name]} AND #{right_col_name} <= #{child[right_col_name]}" +
            " AND #{root_column} = #{child[root_column]} AND #{root_column} != 0"
          )
          
          # update parent_id on child ONLY
          self.class.update_all(
            "#{parent_column} = #{self.id}",
            "id = #{child.id}"
          )
          
          # update myself and upstream to notify we are wider
          self.class.update_all(
            "#{right_col_name} = #{right_col_name} + #{child_occupies}",
            "#{scope_condition} AND #{root_column} = #{self[root_column]} AND (#{depth_column} < #{self[depth_column]} OR id = #{self.id})"
          )
          
          # update items to my right AND downstream of them to notify them we are wider. Will shift root items to the right
          self.class.update_all(
            "#{left_col_name} = #{left_col_name} + #{child_occupies}, " +
            "#{right_col_name} = #{right_col_name} + #{child_occupies}",
            "#{depth_column} >= #{self[depth_column]} " + 
            "AND #{left_col_name} > #{self[right_col_name]}"
          )
        end
        [self, child].map{|e| e.reload }
        true
      end
      
      # Determine lft and rgt for a child item, taking into account the number of child and grandchild nodes it has.
      # Normally you would not use this directly
      def determine_range_for_child(child)
        new_left = begin
          right_bound_child = self.class.find(:first, 
            :conditions => "#{scope_condition} AND #{parent_column} = #{self.id} AND id != #{child.id}", :order => "#{right_col_name} DESC")
          right_bound_child ? (right_bound_child[right_col_name] + 1) : (self[left_col_name] + 1)
        end
        new_right = new_left + (child[right_col_name] - child[left_col_name])
        [new_left, new_right]
      end
      
      # Returns the number of children and grandchildren of this object
      def child_count
        return 0 unless might_have_children? # optimization shortcut
        self.class.count_by_sql("SELECT COUNT(id) FROM #{self.class.table_name} WHERE #{conditions_for_all_children}")
      end
      alias_method :children_count, :child_count
      
      # Shortcut to determine if our left and right values allow for possible children.
      # Note the difference in wording between might_have and has - if this method returns false,
      # it means you should look no further. If it returns true, you should really examine
      # the children to be sure
      def might_have_children?
        (self[right_col_name] - self[left_col_name]) > 1
      end
      
      # Returns a set of itself and all of its nested children
      def full_set(extras = {})
        [self] + all_children
      end
      alias_method :all_children_and_self, :full_set

      # Returns a set of all of its children and nested children
      def all_children(extras = {})
        return [] unless might_have_children? # optimization shortcut
        self.class.scoped(scope_hash_for_branch).find(:all, extras)
      end
      
      # Returns scoping options suitable for fetching all children
      def scope_hash_for_branch
        {:conditions => conditions_for_all_children, :order => "#{left_col_name} ASC" }
      end
      
      # Returns scopint options suitable for fetching direct children
      def scope_hash_for_direct_children
        {:conditions => "#{scope_condition} AND #{parent_column} = #{self.id}", :order => "#{left_col_name} ASC"}
      end
      
      # Get conditions for direct and indirect children of this record
      def conditions_for_all_children
        "#{scope_condition} AND #{root_column} = #{self[root_column]} AND " +
        "#{depth_column} > #{self[depth_column]} AND " +
        "#{left_col_name} > #{self[left_col_name]} AND #{right_col_name} < #{self[right_col_name]}"
      end
      
      # Get conditions to find myself and my siblings
      def conditions_for_self_and_siblings
        "#{scope_condition} AND #{parent_column} = #{self[parent_column]}"
      end
      
      # Get immediate siblings, ordered
      def siblings
        self.class.find(:all, :conditions => "#{conditions_for_self_and_siblings} AND id != #{self.id}", :order => "#{left_col_name} ASC")
      end
      
      # Get myself and siblings, ordered
      def siblings_and_self
        self.class.find(:all, :conditions => conditions_for_self_and_siblings, :order => "#{left_col_name} ASC")
      end
      
      # Returns a set of only this entry's immediate children, also ordered by position
      def direct_children(extras = {})
        return [] unless might_have_children? # optimize!
        self.class.scoped(scope_hash_for_direct_children).find(:all, extras)
      end
      
      # Make this item a root node
      def promote_to_root
        transaction do
          my_width = child_count * 2
        
          # Stash the values because assign_default_left_and_right reassigns them
          old_left, old_right, old_root = self[left_col_name], self[right_col_name], self[root_column]
          self[parent_column] = 0 # Signal the root node
        
          assign_default_left_and_right(my_width)
          
          move_by = self[left_col_name] - old_left
          move_depth_by = self[depth_column]
        
          # bring the child and its grandchildren over
          self.class.update_all( 
            "#{depth_column} = #{depth_column} - #{move_depth_by}," +
            "#{root_column} = #{self.id}," +
            "#{left_col_name} = #{left_col_name} + #{move_by}," +
            "#{right_col_name} = #{right_col_name} + #{move_by}",
            "#{scope_condition} AND #{left_col_name} >= #{old_left} AND #{right_col_name} <= #{old_right}" +
            " AND #{root_column} = #{old_root}"
          )
          self.reload
        end
        true
      end
      
      def register_parent_id_before_update 
        @old_parent_id = self.class.connection.select_value("SELECT #{parent_column} FROM #{self.class.table_name} WHERE id = #{self.id}")
        true
      end
      
      def replant_after_update
        if @old_parent_id.nil? || (@old_parent_id == self[parent_column])
          return true
        # If the new parent_id is nil, it means we are promoted to woot node
        elsif self[parent_column].nil? || self[parent_column].zero?
          promote_to_root
        else
          self.class.find(self[parent_column]).add_child(self)
        end

        true
      end
      
    end #InstanceMethods
  end
end
