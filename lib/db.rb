require 'data_mapper'
DataMapper::Logger.new($stdout, :info)
DataMapper.setup(:default, "sqlite://#{File.expand_path File.dirname(__FILE__)}/dev.db")
# DataMapper.setup :default, {
#   adapter: :postgres,
#   password: '789_random_password_987'
# }
path = File.dirname(File.absolute_path(__FILE__) )
Dir.glob(path + '/db/*').delete_if{ |file| File.directory?(file) || Pathname.new(file).extname != '.rb' }.each{ |file| require file }
DataMapper.finalize
DataMapper.auto_upgrade!
