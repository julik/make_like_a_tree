# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{make_like_a_tree}
  s.version = "1.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Julik"]
  s.date = %q{2009-01-25}
  s.description = %q{Implement orderable trees in ActiveRecord using the nested set model, with multiple roots and scoping, and most importantly user-defined ordering of subtrees. Fetches preordered trees in one go, updates are write-heavy.  This is a substantially butchered-up version/offspring of acts_as_threaded. The main additional perk is the ability to reorder nodes, which are always fetched ordered. Example:  root = Folder.create! :name => "Main folder" subfolder_1 = Folder.create! :name => "Subfolder", :parent_id => root.id subfolder_2 = Folder.create! :name => "Another subfolder", :parent_id => root.id  subfolder_2.move_to_top # just like acts_as_list but nestedly awesome root.all_children # => [subfolder_2, subfolder_1]  See the rdocs for examples the method names. It also inherits the awesome properties of acts_as_threaded, namely materialized depth, root_id and parent_id values on each object which are updated when nodes get moved.  Thanks to the authors of acts_as_threaded, awesome_nested_set, better_nested_set and all the others for inspiration.}
  s.email = ["me@julik.nl"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt", "README.txt"]
  s.files = ["History.txt", "Manifest.txt", "README.txt", "Rakefile", "init.rb", "lib/make_like_a_tree.rb", "test/test_ordered_tree.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/julik/make_like_a_tree}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{make_like_a_tree}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Implement orderable trees in ActiveRecord using the nested set model, with multiple roots and scoping, and most importantly user-defined ordering of subtrees}
  s.test_files = ["test/test_ordered_tree.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<hoe>, [">= 1.8.2"])
    else
      s.add_dependency(%q<hoe>, [">= 1.8.2"])
    end
  else
    s.add_dependency(%q<hoe>, [">= 1.8.2"])
  end
end
