require 'test_helper'

class MapTest < ActiveSupport::TestCase
  setup do
    @map = FactoryBot.create(:available_map)

    FactoryBot.create(:gcp_1, map: @map)
    FactoryBot.create(:gcp_2, map: @map)
    FactoryBot.create(:gcp_3, map: @map)
  end

  teardown do
    delete_created_images(@map)
  end

  test 'be valid' do
    assert @map.valid?
  end

  test 'can have gcps' do
    gcps_count = @map.gcps.count
    assert_equal 3, gcps_count
  end

  test 'can warp successfully' do
    assert_equal :available, @map.status
    assert_not File.exist?(@map.warped_filename)
    resample_option = ' -rn '
    transform_option = ''
    use_mask = false
    @map.warp!(transform_option, resample_option, use_mask)
    assert_equal :warped, @map.status
    assert File.exist?(@map.warped_filename)
  end

  test 'cannot have two maps with the same filename' do
    assert_raise ActiveRecord::RecordInvalid do
      @copymap = FactoryBot.create(:available_map, title: 'copied')
    end
  end

  test 'converts mask to geojson' do
    test_gml = Rails.root.join('test/fixtures/data/test.gml').to_s
    Map.any_instance.stubs(:masking_file_gml).returns(test_gml)
    @map.mask!

    assert_not_nil @map.mask_geojson
    json = JSON.parse(@map.mask_geojson)
    assert_equal 'FeatureCollection', json['type']
  end

  test 'Paperclip cleans filenames' do
    @file = Tempfile.new(%w[filename png])
    @file.stubs(:original_filename).returns("Dublin-P;ettigr ew_Oul'[ton_(ca1850).png")
    map = Map.new
    map.upload = @file

    assert_equal 'Dublin-P_ettigr_ew_Oul__ton__ca1850_.png', map.upload.original_filename

    @file.unlink
  end

  private

  def delete_created_images(map)
    if File.exist?(map.temp_filename)
      # puts "deleted temp #{map.temp_filename}"
      File.delete(map.temp_filename)
    end
    if File.exist?(map.warped_filename)
      # puts "Deleted Map warped #{map.warped_filename}"
      File.delete(map.warped_filename)
    end
    if File.exist?(map.warped_png_filename)
      #  puts "deleted warped png #{map.warped_png_filename}"
      File.delete(map.warped_png_filename)
    end
    return unless File.exist?(map.warped_png_filename + '.aux.xml')

    # puts "deleted warped png #{map.warped_png_filename+".aux.xml"}"
    File.delete(map.warped_png_filename + '.aux.xml')
  end
end
