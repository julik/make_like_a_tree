# -*- ruby -*-

require 'rubygems'
require 'hoe'
require './lib/make_like_a_tree.rb'

# Disable spurious warnings when running tests, ActiveMagic cannot stand -w
Hoe::RUBY_FLAGS.replace ENV['RUBY_FLAGS'] || "-I#{%w(lib test).join(File::PATH_SEPARATOR)}" + 
  (Hoe::RUBY_DEBUG ? " #{RUBY_DEBUG}" : '')

Hoe.new('make_like_a_tree', Julik::MakeLikeTree::VERSION) do |p|
  # p.rubyforge_name = 'OrderedTreex' # if different than lowercase project name
  p.developer('Julik', 'me@julik.nl')
end

# vim: syntax=Ruby
