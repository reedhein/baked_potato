path = File.dirname(File.absolute_path(__FILE__) )
Dir.glob(path + '/concern/*').delete_if{|file| File.directory?(file) }.each{|file| require file}
module Utils
  module SalesForce
    module Concern

    end
  end
end
