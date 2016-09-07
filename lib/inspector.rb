module Inspector
  
  def inspect
    string = "#<#{self.class.name}:#{self.object_id} "
    fields = self.class.inspector_fields.map{|field| "#{field}: #{self.send(field)}"}
    string << fields.join(", ") << ">"
  end
  
  def self.inspected
    @inspected ||= []
  end
  
  def self.included source
    # $stdout.puts "Overriding inspect on #{source}"
    inspected << source
    source.class_eval do
      def self.inspector *fields
        @inspector_fields = *fields
      end
      
      def self.inspector_fields
        @inspector_fields ||= []
      end
    end
  end
end

# Examples

# For use when testing you can class eval the model you want
# to override the inspect behavior on.
# User.class_eval do
#   include Inspector
#   inspector :id, :email, :company_id
# end

# There's also nothing stopping you from doing this in
# any ruby class
# class User
#   # ...
#   include Inspector
#   inspector :id, :email, :company_id
#   #...
# end

# puts User.new.inspect
# => #<User:0x10c7a2f80 id: 1, email: "tyler@example.com", company_id: 1>
