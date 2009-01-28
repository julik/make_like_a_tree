require 'rubygems'
require 'active_record'
require 'active_support'
require 'test/spec'

require File.dirname(__FILE__) + '/../init'

ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :dbfile => ':memory:')
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :nodes, :force => true do |t|

    t.string :name,  :null => false
    t.integer :project_id

    # Bookkeeping for threads
    t.integer :root_id,          :default => 0,   :null => false
    t.integer :parent_id,        :default => 0,   :null => false
    t.integer :depth,            :maxlength => 5, :default => 0,    :null => false
    t.integer :lft,              :default => 0,   :null => false
    t.integer :rgt,              :default => 0,   :null => false
  end
  
  # Anonimous tables for anonimous classes
  (1..20).each do | i |
    create_table "an#{i}s", :force => true do # anis!
    end
  end
end

class NodeTest < Test::Unit::TestCase

  class Node < ActiveRecord::Base
    set_table_name "nodes"
    make_like_a_tree :scope => :project
    def _lr
      [lft, rgt]
    end
  end
  
  def emit(attributes = {})
    Node.create!({:project_id => 1}.merge(attributes))
  end
  
  def emit_many(how_many, extras = {})
    (1..how_many).map{|i| emit({:name => "Item_#{i}"}.merge(extras)) }
  end

  def reload(*all)
    all.flatten.map(&:reload)
  end
  
  def setup
    Node.delete_all
    super
  end
  
  # Silence!
  def default_test; end
end

context "A Node with attributes that change in flight should", NodeTest do
  specify "return same siblings no matter what parent_id the record has assigned" do
    node1, node2, node3 = emit_many(3)
    reload(node1, node2, node3)
    
    node1.parent_id = 100
    node2.parent_id = 300
    node3.parent_id = 600
    
    node1.siblings.should.equal [node2, node3]
  end
  
  specify "return same all_children no matter what left and right the record has assigned" do
    node1, node2, node3 = emit_many(3)
    children = emit_many(10, :parent_id => node1.id)
    
    reload(node1)
    node1.all_children.should.equal children
    
    node1.lft, node1.rgt, node1.depth, node1.root_id = 300, 400, 23, 67
    
    node1.all_children.should.equal children
  end
end

context "A Node used with OrderedTree should", NodeTest do
  Node = NodeTest::Node
  
  specify "support full_set" do
    folder1, folder2 = emit(:name => "One"), emit(:name => "Two")
    three = emit(:name => "subfolder", :parent_id => folder1.id)
    
    folder1.all_children_and_self.should.equal folder1.full_set
  end
  
  specify "return a proper scope condition" do
    Node.new(:project_id => 1).scope_condition.should.equal "project_id = 1"
    Node.new(:project_id => nil).scope_condition.should.equal "project_id IS NULL"
  end
  
  specify "return a bypass scope condition with no scope" do
    class An2 < ActiveRecord::Base
      make_like_a_tree
    end
    An2.new.scope_condition.should.equal "(1=1)" 
  end
  
  specify "return a proper left and right column if they have been customized" do
    class An1 < ActiveRecord::Base
      make_like_a_tree :left_column => :foo, :right_column => :bar
    end
    An1.new.left_col_name.should.equal "foo"
    An1.new.right_col_name.should.equal "bar"
  end
   
  specify "return a proper depth column if it has been customized" do
    class An3 < ActiveRecord::Base
      make_like_a_tree :depth_column => :niveau
    end
    An3.new.depth_column.should.equal "niveau"
  end
  
  specify "create root nodes with ordered left and right" do
    groups = (0...2).map do | idx |
      emit :name => "Group_#{idx}"
    end
    reload(groups)
    
    groups[0]._lr.should.equal [1, 2]
    groups[1]._lr.should.equal [3,4]
  end
  
  specify "create a good child node" do
    
    root_node = emit :name => "Mother"
    child_node = emit :name => "Daughter", :parent_id => root_node.id
    
    reload(root_node, child_node)
    
    root_node.child_can_be_added?(child_node).should.blaming("possible move").equal true
    root_node._lr.should.blaming("root node with one subset is 1,4").equal [1, 4]
    child_node._lr.should.blaming("first in nested range is 2,3").equal [2, 3]
  end
  
  specify "create a number of good child nodes" do
    
    root_node = emit :name => "Mother"
    child_nodes = ["Daughter", "Brother"].map { |n| emit :name => n, :parent_id => root_node.id }
    
    reload(root_node, child_nodes)
    
    root_node._lr.should.blaming("extended range").equal [1, 6]
    child_nodes[0]._lr.should.blaming("first in sequence is 2,3").equal [2, 3]
    child_nodes[1]._lr.should.blaming("second in sequence is 4,5").equal [4, 5]
    
    child_nodes.each do | cn |
      cn.depth.should.blaming("depth increase").equal 1
      cn.root_id.should.blaming("proper root assignment").equal root_node.id
      cn.parent_id.should.blaming("parent assignment").equal root_node.id
    end
  end
  
  specify "shift siblings to the right on child assignment to their left neighbour" do
    root_node = emit :name => "Root one"
    
    sub_node = emit :name => "Child 1", :parent_id => root_node.id
    sub_node_sibling = emit :name => "Child 2", :parent_id => root_node.id
    
    reload(sub_node_sibling)
    sub_node_sibling._lr.should.equal [4,5]

    # Now inject a child into sub_node
    grandchild = emit :name => "Grandchild via Child 1", :parent_id => sub_node.id
    
    reload(sub_node_sibling)
    sub_node_sibling._lr.should.blaming("shifted right because a child was injected to the left of us").equal [6,7]
    
    reload(root_node)
    root_node._lr.should.blaming("increased range for the grandchild").equal [1,8]
  end
  
  specify "make nodes their own roots" do
    a, b = %w(a b).map{|n| emit :name => n }
    a.root_id.should.equal a.id
    b.root_id.should.equal b.id
  end
  
  specify "replant a branch" do
    root_node_1 = emit :name => "First root"
    root_node_2 = emit :name => "Second root"
    root_node_3 = emit :name => "Third root"
    
    # Now make a subtree on the third root node
    child = emit :name => "Child", :parent_id => root_node_3.id
    grand_child = emit :name => "Grand child", :parent_id => child.id
    grand_grand_child = emit :name => "Grand grand child", :parent_id => grand_child.id
    
    reload(root_node_1, root_node_2, root_node_3, child, grand_child, grand_grand_child)
    
    child._lr.should.blaming("the complete branch indices").equal [6,11]
    root_node_3._lr.should.blaming("inclusive for the child branch").equal [5, 12]

    root_node_1.add_child(child) 
    
    reload(root_node_1, root_node_2)
    
    root_node_1._lr.should.blaming("branch containment expanded the range").equal [1, 8]
    root_node_2._lr.should.blaming("shifted right to make room").equal [9, 10]
  end
  
  specify "report size after moving a branch from underneath" do
    root_node_1 = emit :name => "First root"
    root_node_2 = emit :name => "First root"
    
    child = emit :name => "Some child", :parent_id => root_node_2.id
    
    root_node_2.reload
    
    root_node_2.might_have_children?.should.blaming("might_have_children? is true - our indices are #{root_node_2._lr.inspect}").equal true
    root_node_2.child_count.should.blaming("only one child available").equal 1
    
    # Now replant the child
    root_node_1.add_child(child)
    reload(root_node_1, root_node_2)
    
    root_node_2.child_count.should.blaming("all children removed").be.zero
    root_node_1.child_count.should.blaming("now has one child").equal 1
  end
  
  specify "return siblings" do
    root_1 = emit :name => "Foo"
    root_2 = emit :name => "Bar"
    
    reload(root_1, root_2)
    
    root_1.siblings.should.equal [root_2]
    root_2.siblings.should.equal [root_1]
  end
  
  specify "return siblings and self" do
    root_1 = emit :name => "Foo"
    root_2 = emit :name => "Bar"
    
    reload(root_1, root_2)
    
    root_1.siblings_and_self.should.equal [root_1, root_2]
    root_2.siblings_and_self.should.equal [root_1, root_2]
  end
  
  specify "provide index_in_parent" do
    root_nodes  = (0...3).map do | i |
      emit :name => "Root_#{i}"
    end

    root_nodes.each_with_index do | rn, i |
      rn.should.respond_to :index_in_parent
      rn.index_in_parent.should.blaming("is at index #{i}").equal i
    end
  end
  
  specify 'do nothing on move when only item in the list' do
     a = emit :name => "Boo"
     a.move_to(0).should.equal true
     a.move_to(200).should.equal true
  end
  
  specify "do nothing if we move from the same position to the same position" do
    a = emit :name => "Foo"
    b = emit :name => "Boo"
    
    a.move_to(0).should.equal true
    b.move_to(1).should.equal true
  end
  
  specify "move a root node up" do
    root_1 = emit :name => "First root"
    root_2 = emit :name => "Second root"
    root_2.move_to(0)
    
    reload(root_1, root_2)
    
    root_1._lr.should.equal [3, 4]
    root_2._lr.should.equal [1, 2]
  end
  
  specify "reorder including subtrees" do
    root_1 = emit :name => "First root"
    root_2 = emit :name => "Second root with children"
    4.times{ emit :name => "Child of root2", :parent_id => root_2.id }
    
    reload(root_2)
    root_2._lr.should.equal [3, 12]
    
    root_2.move_to(0)
    reload(root_2)
    
    root_2._lr.should.blaming("Shifted range").equal [1, 10]
    root_2.children_count.should.blaming("the same children count").equal 4
    
    reload(root_1)
    root_1._lr.should.blaming("Shifted down").equal [11, 12]
    root_1.children_count.should.blaming("the same children count").be.zero
  end
  
  specify "support move_up" do
    root_1, root_2 = emit(:name => "First"), emit(:name => "Second")
    root_2.should.respond_to :move_up
    
    root_2.move_up

    reload(root_1, root_2)
    root_2._lr.should.equal [1,2]
  end
  
  specify "support move_down" do
    root_1, root_2 = emit(:name => "First"), emit(:name => "Second")

    root_1.should.respond_to :move_down
    root_1.move_up

    reload(root_1, root_2)
    root_2._lr.should.equal [1,2]
    root_1._lr.should.equal [3,4]
  end

  specify "support move_to_top" do
    root_1, root_2, root_3 = emit(:name => "First"), emit(:name => "Second"), emit(:name => "Third")

    root_3.should.respond_to :move_to_top
    root_3.move_to_top
    reload(root_1, root_2, root_3)
    
    root_3._lr.should.blaming("is now on top").equal [1,2]
    root_1._lr.should.blaming("is now second").equal [3,4]
    root_2._lr.should.blaming("is now third").equal [5,6]
  end
  
  specify "support move_to_bottom" do
    root_1, root_2, root_3, root_4 = (1..4).map{|e| emit :name => "Root_#{e}"}
    root_1.should.respond_to :move_to_bottom
    
    root_1.move_to_bottom
    reload(root_1, root_2, root_3, root_4)
    
    root_2._lr.should.blaming("is now on top").equal [1,2]
    root_1._lr.should.blaming("is now on the bottom").equal [7,8]
  end

  specify "support move_to_top for the second item of three" do
    a, b, c = emit_many(3)
    b.move_to_top
    reload(a, b, c)
    
    a._lr.should.equal [3, 4]
    b._lr.should.equal [1, 2]
    c._lr.should.equal [5, 6]
  end
  
  specify "should not allow reparenting an item into its child" do
    root = emit :name => "foo"
    child = emit :name => "bar", :parent_id => root.id
    reload(root, child)
    
    child.child_can_be_added?(root).should.blaming("Impossible move").equal false
    lambda { child.add_child!(root)}.should.raise(Julik::MakeLikeTree::ImpossibleReparent)
    child.add_child(root).should.equal false
  end
  
  specify "support additional find options via scoped finds on all_children" do
    root = emit :name => "foo"
    child = emit :name => "bar", :parent_id => root.id
    another_child = emit :name => "another", :parent_id => root.id
    
    reload(root)

    root.all_children.should.equal [child, another_child]
    root.all_children(:conditions => {:name => "another"}).should.equal [another_child]
  end
  
  specify "support additional find options via scoped finds on direct_children" do
    root = emit :name => "foo"
    anoter_root = emit :name => "another"
    
    child = emit :name => "bar", :parent_id => root.id
    another_child = emit :name => "another", :parent_id => root.id
    
    reload(root)

    root.direct_children.should.equal [child, another_child]
    root.direct_children(:conditions => {:name => "another"}).should.equal [another_child]
  end
  
  specify "support additional find options via scoped finds on full_set" do
    root = emit :name => "foo"
    anoter_root = emit :name => "another"
    child_1 = emit :name => "another",  :parent_id => root.id
    child_2 = emit :name => "outsider", :parent_id => root.id
    
    reload(root)
    
    root.full_set(:conditions => {:name => "another"}).should.equal [root, child_1]
  end
  
  specify "support promote_to_root" do
    a, b = emit_many(2)
    c = emit(:name => "Subtree", :parent_id => a.id)
    
    reload(a, b, c)
    c.promote_to_root
    
    reload(a, b, c)
    
    c.depth.should.blaming("is at top level").equal 0
    c.root_id.should.blaming("is now self-root").equal c.id
    c._lr.should.blaming("now promoted to root").equal [7, 8]
  end
  
  specify "support replanting by changing parent_id" do
    a, b = emit_many(2)
    sub = emit :name => "Child", :parent_id => a.id
    sub.update_attributes(:parent_id => b.id)

    reload(a, b, sub)
    a.all_children.should.blaming("replanted branch from there").not.include( sub)
    b.all_children.should.blaming("replanted branch here").include( sub)
  end
  
end
