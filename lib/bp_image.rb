class BPImage
  attr_accessor :db_image, :path, :sf_client, :box_client, :db

  def initialize(image_path)
    @path           = image_path.is_a?(CacheFolder) ? Pathname.new(image_path.path) : Pathname.new(image_path)
    @db             = DB::ImageProgressRecord.find_from_path(@path)
    binding.pry unless @db
    @cache_folder   = CacheFolder.new(@path)
    @sf_client      = Utils::SalesForce::Client.new
    @box_client     = Utils::Box::Client.new
  end

  def lock
    @db_image.update(locked: true)
  end

  def self.random_unlocked
    records = DB::ImageProgressRecord.all(parent_type: 'opportunity', locked: false, complete: false, ext: %w(.jpg .png .pdf), date: Date.today.to_s)
    records.delete_if{|x| x.file_id.nil?}
    record = records.sample
    binding.pry unless record
    bpi = BPImage.new(record.full_path)
    bpi.db_image = record
    bpi
  end

  def self.find_by_id(id)
    records = DB::ImageProgressRecord.all(file_id: id)
    if records.count > 1 && records.map(&:sha1).uniq.count == 1
      latest_record = records.sort_by{|r| Date.parse(r.date)}.last
      records.each{|r| r.destroy unless r == latest_record}
    end
    bpi = self.new(records.first.full_path)
    bpi.db_image = records.first
    bpi
  end

  def self.id_from_path(path)
    begin
      db = DB::ImageProgressRecord.all(full_path: path)
      binding.pry if db.count > 1
      binding.pry unless db.present?
      db.first.file_id
    rescue => e
      puts e
      ap e.backtrace
      binding.pry
    end
  end

  def self.find_id_from_interwebs(path)
    if CacheFolder.parent_type(path) == :salesforce
      result = id_for_salesforce_path(path)
    else #box
      result = id_for_box_with_given_path(path)
    end
    update_file_id_for_databse(path, result) if result
    result
  end

  def self.update_file_id_for_databse(path,result)
    ipr = DB::ImageProgressRecord.all(full_path: path)
    if ipr.count > 1
      puts 'uh oh'
      binding.pry
    else
      ipr.first.file_id = result
    end
    ipr.first.save
    puts result if ipr.first.file_id != result
  end

  def self.id_for_box_with_given_path(path)
    bp = BPImage.new(path)
    box_client = bp.box_client
    box_folder_id = path.parent.basename.to_s
    begin
      box_folder    = box_client.folder_from_id(box_folder_id)
    rescue Boxr::BoxrError => e
      return nil if e.to_s =~ /404: Item is trashed/
    rescue => e
      ap e.backtrace
      binding.pry
      return nil
    end
    file_sha1     = Digest::SHA1.hexdigest(path.read)
    box_file      = box_folder.files.detect do |bf|
      bf.sha1 == file_sha1
    end
    box_file.try(:id)
  end

  def self.id_for_salesforce_path(path)
    bp = BPImage.new(path)
    sf_client  = bp.sf_client
    sobject_id = path.parent.basename.to_s
    query = "SELECT id, Name, Body FROM Attachment where parentid = '#{sobject_id}'"
    attachments = sf_client.custom_query(query: query)
    files_of_same_name = attachments.select{|a| a.name == path.basename.to_s}
    if files_of_same_name.count > 1
      file_sha1 = Digest::SHA1.hexdigest(path.read)
      sf_attachment = attachments.detect{|a| file_sha1 == Digest::SHA1.hexdigest(a.api_object.Body) }
    else
      sf_attachment = attachments.first
    end
    sf_attachment.id
  end

  def self.find_all_by_sha1(sha1)
    DB::ImageProgressRecord.all( sha1: sha1 )
  end

  def parent_type
    @db.parent_type
  end

  def cloud_path
    parent_type + '/' + @path.parent.basename.to_s
  end

  def id
    @db.file_id
  end

  def ext
    @db_image.ext
  end

  def full_path
    @db_image.full_path
  end

  def meta
    @cache_folder.meta
  end

  def name
    @path.basename
  end

  def opportunity
    @cache_folder.opportunity
  end

  def cases #presume bp_image is opportunity
    cases_folder = @path.parent + 'cases'
    return [] unless cases_folder.exist?
    cases_folder.children.select do |entity|
      entity.directory? && entity.basename.to_s =~ /^500/
    end.map do |case_folder|
      CacheFolder.new(case_folder)
    end
  end
end
