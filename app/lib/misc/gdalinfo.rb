def get_raster_extents(filename)
  _, stdout, = Open3.popen3("#{GDAL_PATH}gdalinfo", "#{filename}")
  info = stdout.readlines.to_s
  _, west, south = info.match(/Lower Left\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a
  _, east, north = info.match(/Upper Right\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a
  [west.to_f, south.to_f, east.to_f, north.to_f]
end

def raster_bands_count(filename)
  _, stdout, = Open3.popen3("#{GDAL_PATH}gdalinfo", "#{filename}")
  info = stdout.readlines
  bands = info.select { |line| line.encode('utf-8', invalid: :replace, replace: '').scrub.match(/^Band\s\d/) }

  bands.size
end

def has_palette_colortable?(filename)
  _, stdout, = Open3.popen3("#{GDAL_PATH}gdalinfo", "#{filename}")
  info = stdout.readlines
  bands = info.select { |line| line.encode('utf-8', invalid: :replace, replace: '').scrub.match(/^Band\s\d/) }
  first_band = bands.first

  first_band.include?('ColorInterp=Palette')
end
