class Layer < ActiveRecord::Base
  has_many :layers_maps, dependent: :destroy
  has_many :maps, through: :layers_maps
  belongs_to :user, optional: true

  acts_as_commentable

  include PgSearch::Model

  multisearchable against: %i[name description]

  validates :name, presence: true
  validates :depicts_year, length: { maximum: 4, allow_blank: true }
  validates :depicts_year, numericality: { if: proc { |c| c.depicts_year.present? } }

  scope :with_year, -> { where(depicts_year: 'is not null').order(:maps_count) }
  scope :visible, -> { where(is_visible: true).order(:id) }
  scope :with_maps, -> { where('rectified_maps_count >= 1').order(:rectified_maps_count) }

  after_create :update_layer
  after_destroy :delete_tileindex

  def tileindex_filename = id.to_s + '.shp'

  def tileindex_dir
    defined?(TILEINDEX_DIR) ? TILEINDEX_DIR : Rails.root.join('db/maptileindex').to_s
  end

  def tileindex_path = File.join(tileindex_dir, tileindex_filename)

  def thumb
    if maps.first.nil?
      'missing.png'
    elsif !maps.first.public?
      'private.png'
    else
      maps.first.upload.url(:thumb)
    end
  end

  def update_layer
    create_tileindex
    set_bounds
    Rails.cache.delete_matched "*/mosaics/tile/#{id}/*"
    Rails.cache.delete_matched "*/mosaics/wms/#{id}?*"
  end

  def update_counts
    update_column(:maps_count, maps.real_maps.length)
    update_column(:rectified_maps_count, maps.warped.count)
  end

  # def rectified_maps_count
  #  self.maps.warped.count
  # end

  def rectified_percent
    percent = ((rectified_maps_count.to_f / maps_count.to_f) * 100).to_f
    percent.nan? ? 0 : percent
  end

  def publish
    # empty method for publish action of layer
  end

  def merge(destination_layer_id)
    dest_layer = Layer.find(destination_layer_id)
    logger.info "layer #{id} merge to #{dest_layer.id}"

    layers_maps.each do |map_layer|
      map_layer.layer = dest_layer
      map_layer.save
    end

    update_counts
    dest_layer.update_counts
    reload # possibly not needed
    dest_layer.reload # possibly not needed
    dest_layer.update_layer

    true
  end

  # removes map from a layer
  def remove_map(map_id)
    logger.info "layer #{id} will have map #{map_id} removed from it"
    map_layer = LayersMap.where(['map_id = ? and layer_id = ?', map_id, id]).first
    logger.info 'this relationship to be deleted'
    logger.info map_layer.inspect
    map_layer.destroy
    update_counts
    update_layer
  end

  # gdaltindex [-tileindex field_name] [-write_absolute_path] [-skip_different_projection] index_file [gdal_file]*
  def create_tileindex(custom_path = nil)
    logger.info('create tileindex')
    tileindex = custom_path || tileindex_path
    if maps.warped.empty?
      result = false
    else
      delete_tileindex(tileindex)
      map_list = ''
      # only make a tileindex if the maps are warped.
      maps.warped.each { |map| map_list += (map.warped_filename + ' ') }
      command = "gdaltindex -write_absolute_path #{tileindex} #{map_list}"
      logger.info(command)

      _, stdout, stderr = Open3.popen3(command)
      stdout.readlines.to_s
      err = stderr.readlines.to_s

      if !err.match("ERROR 4: Unable to open #{tileindex}").nil? || err.size <= 0 # error saying "Unable to open spec/fixtures/maps/deleteme.shp" is actually okay!!
        result = true
      else
        logger.error('ERROR with gdaltindex ' + err)
        result = false
      end
    end

    result
  end

  def get_bounds
    if bbox.blank?
      create_tileindex
      set_bounds
    else
      bbox
    end
  end

  # sets bbox
  def set_bounds(custom_path = nil)
    logger.debug 'set_bounds in layer'
    tileindex = custom_path || tileindex_path
    if maps.warped.empty?
      extent = nil
    else
      command = "ogrinfo #{tileindex} -al -so -ro"
      logger.info command
      # stdin, stdout, stderr = Open3::popen3(command)
      stdout, stderr = Open3.capture3(command)
      sout = stdout
      serr = stderr
      if serr.blank?
        extent = sout.scan(/^\w+: \(([0-9\-.]+), ([0-9\-.]+)\) - \(([0-9\-.]+), ([0-9\-.]+)\)$/).flatten.join(',')

        self.bbox = extent.to_s
        extents =  extent.split(',').collect { |f| f.to_f }
        poly_array = [
          [extents[0], extents[1]],
          [extents[2], extents[1]],
          [extents[2], extents[3]],
          [extents[0], extents[3]],
          [extents[0], extents[1]]
        ]
        logger.error poly_array.inspect

        self.bbox_geom = GeoRuby::SimpleFeatures::Polygon.from_coordinates([poly_array]).as_wkt

        @bounds = extent
        save!
      else
        logger.error 'Error set bounds with layer get extent ' + serr
      end

    end
    extent
  end

  ##################
  # PRIVATE
  ##################

  private

  def delete_tileindex(custom_path = nil)
    tileindex = custom_path || tileindex_path
    if File.exist?(tileindex)
      basename = File.basename(tileindex, '.shp')
      basedir = File.dirname(tileindex)
      logger.info 'deleting tileindex'
      File.delete(tileindex) # shp
      File.delete(File.join(basedir, basename + '.dbf'))
      File.delete(File.join(basedir, basename + '.shx'))
      File.delete(File.join(basedir, basename + '.qix')) if File.exist?(File.join(basedir, basename + '.qix'))
      result = true
    else
      result = false
    end

    result
  end
end
