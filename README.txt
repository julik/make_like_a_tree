= make_like_a_tree

http://github.com/julik/make_like_a_tree

== DESCRIPTION:

Implement orderable trees in ActiveRecord using the nested set model, with multiple roots and scoping, and most importantly user-defined
ordering of subtrees. Fetches preordered trees in one go, updates are write-heavy.

This is a substantially butchered-up version/offspring of acts_as_threaded. The main additional perk is the ability
to reorder nodes, which are always fetched ordered. Example:

  root = Folder.create! :name => "Main folder"
  subfolder_1 = Folder.create! :name => "Subfolder", :parent_id => root.id
  subfolder_2 = Folder.create! :name => "Another subfolder", :parent_id => root.id
  
  subfolder_2.move_to_top # just like acts_as_list but nestedly awesome
  root.all_children # => [subfolder_2, subfolder_1]

See the rdocs for examples the method names. It also inherits the awesome properties of acts_as_threaded, namely
materialized depth, root_id and parent_id values on each object which are updated when nodes get moved.

Thanks to the authors of acts_as_threaded, awesome_nested_set, better_nested_set and all the others for inspiration.


== FEATURES/PROBLEMS:

* Currently there is no clean way to change the column you scope on
* Use create with parent_id set to the parent id (obvious, but somehow blocked in awesome_nested_set)
* Ugly SQL
* The node counts are currently not updated when a node is removed from a subtree and replanted elsewhere, 
  so you cannot rely on (right-left)/2 to get the child count 
* You cannot replant a node by assigning a new parent_id, add_child needed instead
* The table needs to have proper defaults otherwise undefined behavior can happen. Otherwise demons 
  will fly out of your left nostril and make you rewrite the app in inline PHP.

== SYNOPSIS:
  
  class NodeOfThatUbiquitousCms < ActiveRecord::Base
    make_like_a_tree
    
    # Handy for selects and tree text
    def indented_name
      ["-" * depth.to_i, name].join
    end
  end
  
== REQUIREMENTS:

Use the following migration (attention! dangerous defaults ahead!):

  create_table :nodes do |t|
    # Bookkeeping for threads
    t.integer :root_id,          :default => 0,   :null => false
    t.integer :parent_id,        :default => 0,   :null => false
    t.integer :depth,            :default => 0,   :null => false
    t.integer :lft,              :default => 0,   :null => false
    t.integer :rgt,              :default => 0,   :null => false
  end

== INSTALL:

Add a bare init file to your app and there:

  require 'make_like_tree'
  Julik::MakeLikeTree.bootstrap!

Or just vendorize it, it has a built-in init.rb. You can also use the
plugin without unpacking it, to do so put the following in the config:

  config.gem "make_like_a_tree"
  config.after_initialize { Julik::MakeLikeTree.bootstrap! }

== LICENSE:

(The MIT License)

Copyright (c) 2009 Julik Tarkhanov <me@julik.nl>

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
