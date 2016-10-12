class FileRename
  def initialize(proposed_name, id, key, secret)
    @type = determine_client_by_id(id)
    if @type == :salesforce
      RestForce::Client.new()
    else
      BoxClient.new()
    end
  end

  def determine_client_by_id(id)
    if id =~ /^00P/
      :salesforce
    else
      :box
    end
  end
end
