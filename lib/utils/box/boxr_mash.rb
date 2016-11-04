class BoxrMash
  require_relative './concern/db'
  include Utils::Box::Concern::DB #feels weird that this is required

  def client
    @client ||= Utils::Box::Client.new
  end

  def details
    client.folder(self)
  end

  def folders
    folder_items = client.folder_items(self)
    return [] unless folder_items
    folders = folder_items.select do |entry|
      entry.type == 'folder'
    end
    folders.map do |f|
      convert_api_object_to_local_storage(f)
    end
  end

  def items
    client.folder_items(self)
  end

  def files
    folder_items = client.folder_items(self)
    return [] unless folder_items
    files = folder_items.select do |entry|
      entry.type == 'file'
    end
    files.map do |f|
      convert_api_object_to_local_storage(f)
    end
  end

  def download
    if self.fetch('type') == 'file'
      client.download_file(self)
    elsif self.fetc('type') == 'folder'
      self.files.each do |file|
        file.download
      end
    end
  end

  def create_folder(name)
    client.create_folder(name , self) #returns details of folder
  end

  def opportunity_finance_template
    cleint.folder(8433174681)
  end

  def path
    paths = get_details(:path_collection).entries.map do |entry|
      entry.name
    end
    ["", paths, self.name].join('/')
  end

  private

  def get_details(attribute)
    self.send(attribute) || self.details.send(attribute)
  end
  
end
