class OldCacheFolder < CacheFolder
  attr_reader :cache_folder, :box_public, :box_private, :cache_folder, :id, :folder, :path

  def self.cache_folder
    '/Users/voodoologic/Sandbox/cache_folder'
  end

  private

  def get_meta_from_folder
    match = nil
    Dir.glob(@cache_folder + '/*').detect do |path|
      match = path.match( /(?<private>\d+)_#{@opp_id}_(?<public>\d+)/ )
    end
    [match[0], match[:private], match[:public]]
  end

  def get_images
    path_to_images = Pathname.new([@cache_folder, @folder].join('/'))
    Dir.glob(path_to_images.to_s + '/*').select do |file|
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
