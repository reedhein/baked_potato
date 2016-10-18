class FileRename < Action
  attr_accessor :box_client, :sf_client
  def initialize(*args)
    super(*args)
  end

  def perform
    type = file_type_by_id(@source_id)
    if type == :salesforce
      @sf_client.update('Attachment', Id: @id, Name: @rename)
    else
      @box_client.update_file(box_file, name: @proposed_name)
    end
    CacheFolder.new(@record.full_path).rename(rename)
    @record.rename(rename)
  end

end
