path = File.dirname(File.absolute_path(__FILE__) )
require path + '/sales_force/base'
Dir.glob(path + '/sales_force/*').delete_if{|file| File.directory?(file) }.each{|file| require file}
module Utils
  module SalesForce
    def self.format_time_to_soql(time)
      case time
      when String
        _time = DateTime.parse(time)
      when Time, Date
        _time = time.to_datetime
      else
        _time = time
      end
      _time.strftime("%Y-%m-%dT%H:%M:%S%z").insert(-3, ':')
    end

    def self.soql_time_to_datetime(time)
      DateTime.parse(time.gsub("T", ' ').gsub(/\.\d+(?:\+|-)\d+/,' '))
    end
  end
end
