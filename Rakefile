# -*- ruby -*-

require 'rubygems'
require 'hoe'
require './lib/make_like_a_tree'

# Disable spurious warnings when running tests, ActiveMagic cannot stand -w
Hoe::RUBY_FLAGS.gsub!(/^-w/, '')

Hoe.spec('make_like_a_tree') do |p|
  p.version = Julik::MakeLikeTree::VERSION
  p.developer('Julik Tarkhanov', 'me@julik.nl')
end

# vim: syntax=Ruby
