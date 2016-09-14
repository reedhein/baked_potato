class NewCacheFolder < CacheFolder
  attr_reader :cache_folder, :box_public, :box_private, :cache_folder, :id, :folder, :type, :path

  def self.cache_folder
    '/Users/voodoologic/Sandbox/cache_folder'
  end

  def recursive_items
    Dir.glob(@location + '**/*').map{|x| Pathname.new(x)}
  end

  def direct_items
    @location.children
  end

  def details
    case type
    when :case
      single_case_query
    when :opportunity
      single_opp_query
    when :box
      @box_client.folder(@id)
    end
  end

  def self.cache_folder
    Pathname.new('/Users/voodoologic/Sandbox/formatted_cache_folder')
  end

  private

  def single_case_query
    query = <<-EOF
      SELECT id, name,
      (SELECT id, name FROM Attachments)
      FROM #{type}
      WHERE id = '#{id}'
    EOF
    @sf_client.custom_query(query: query).first
  end

  def single_opp_query()
    query = <<-EOF
      SELECT id, name,
      (SELECT id, name FROM Attachments)
      FROM #{@type}
      WHERE id = '#{@id}'
    EOF
    @sf_client.custom_query(query: query).first
  end

  def get_images
    path_to_images = Pathname.new(@location)
    path_to_images.children.select do |file|
      ['.pdf', '.jpg', '.jpeg', '.png', '.gif'].include? Pathname.new(file).extname
    end.map do |image|
      BPImage.new(Pathname.new(image), self)
    end
  end

end

class BPImage
  attr_accessor :db_image
  def initialize(image, cache_folder)
    @image    = Pathname.new(image)
    @db_image = DB::ImageProgressRecord.find(opportunity_id: cache_folder.opp_id)
  end

  def lock
    @db_image.update(locked: true)
  end

  def self.random_unlocked
    records = DB::ImageProgressRecord.all(locked: false, complete: false, type: '.pdf') ||
      DB::ImageProgressRecord.all(locked: false, complete: false, type: '.png') ||
      DB::ImageProgressRecord.all(locked: false, complete: false, type: '.jpg')
    record = records.sample
    cf = CacheFolder.new(opp_id: record.opportunity_id)
    path_to_image = Pathname.new([cf.cache_folder, cf.folder, record.filename].join('/'))
    bpi = BPImage.new(path_to_image, cf)
    bpi.db_image = record
    bpi
  end

  def full_path
    @db_image.full_path
  end
end
