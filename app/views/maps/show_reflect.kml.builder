bbox = params[:bbox] || @map.bounds
bounds = bbox.split(',')
wms = 'http://' + request.host_with_port + '/cgi/mapserv.cgi' + '?map=' +
      Map.mapfile_path(params[:id]) + '&layers=' + params[:id].to_s +
      '&request=GetMap&version=1.1.1&styles=&format=image/png&srs=epsg:4326&exceptions=application/vnd.ogc.se_inimage' +
      '&WIDTH=1022&HEIGHT=817&bbox=' + bbox # we'll hardcode the width and height

xml.instruct! :xml
xml.kml(xmlns: 'http://www.opengis.net/kml/2.2') do
  xml.Folder do
    xml.open(1)
    xml.name("Map Warper #{@map.title.to_xs}")
    xml.description('Containing warped images and maps.')
    xml.GroundOverlay do
      xml.name(@map.title.to_xs)
      xml.description(@map.description.to_xs)
      xml.Icon do
        xml.href do
          xml.cdata!(wms)
        end
      end
      xml.LatLonBox do
        xml.north(bounds[3])
        xml.south(bounds[1])
        xml.east(bounds[2])
        xml.west(bounds[0])
        xml.rotation(0)
      end
    end
  end
end
