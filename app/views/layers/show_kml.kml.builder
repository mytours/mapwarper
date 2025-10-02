# this acts as a kml reflector, called from the show as 8978.kml for example
# thanks to Jason Birch messily ported from http://www.jasonbirch.com/wms2kml/wms2kml.phps

bbox = @layer.get_bounds
bounds = bbox.split(',')
west = bounds[0]
south = bounds[1]
east = bounds[2]
north = bounds[3]
width = 256
height = 256
depictsYear = @layer.depicts_year

wms_baseurl = "#{request.scheme}://" + request.host_with_port + url_for(controller: 'layers', action: 'wms',
                                                                        id: @layer)
this_baseurl = "#{request.scheme}://" + request.host_with_port + url_for(controller: 'layers', action: 'show',
                                                                         id: @layer, format: 'kml')
xml.instruct! :xml
xml.kml(xmlns: 'http://www.opengis.net/kml/2.2') do
  # xml.NetworkLinkControl{
  #  xml.minRefreshPeriod(3600)
  # }
  xml.Document do
    if params[:DBOX]
      coords = params[:DBOX].split(',')
      west = coords[0].to_f
      south = coords[1].to_f
      east = coords[2].to_f
      north = coords[3].to_f
      drawOrder = coords[4].to_i
      baseurl = wms_baseurl + '?service=wms&VERSION=1.1.1&request=GetMap&srs=EPSG:4326&width=' + width.to_s + '&height=' + height.to_s + '&format=image/png&transparent=true&layers=image&styles='
      xml.Region do
        xml.Lod do
          xml.minLodPixels(128)
          xml.maxLodPixels(-1)
        end
        xml.LatLonBox do
          xml.north(north)
          xml.south(south)
          xml.east(east)
          xml.west(west)
        end
      end
      xml.GroundOverlay do
        if depictsYear.present?
          xml.TimeStamp do
            xml.when(depictsYear)
          end
        end
        xml.drawOrder(drawOrder)
        xml.Icon do
          url_to_use = baseurl + '&bbox=' + west.to_s + ',' + south.to_s + ',' + east.to_s + ',' + north.to_s
          xml.href do
            xml.cdata!(url_to_use)
          end
        end
        xml.LatLonBox do
          xml.north(north)
          xml.south(south)
          xml.east(east)
          xml.west(west)
        end
      end
      xval = []
      yval = []
      xval[0] = west
      xval[1] = west - ((west - east) / 2)
      xval[2] = east

      yval[0] = south
      yval[1] = south - ((south - north) / 2)
      yval[2] = north

      drawOrder += 1

      (0..1).each do |x|
        (0..1).each do |y|
          xml.NetworkLink do
            # xml.visibility(1)
            xml.Region do
              xml.LatLonAltBox do
                xml.north(yval[y + 1])
                xml.south(yval[y])
                xml.east(xval[x + 1])
                xml.west(xval[x])
              end
              xml.Lod do
                xml.minLodPixels(128)
                xml.maxLodPixels(-1)
              end
            end
            xml.Link do
              xml.viewRefreshMode('onRequest')
              xml.href do
                xml.cdata!(this_baseurl + '?DBOX=' + xval[x].to_s + ',' + yval[y].to_s + ',' + xval[x + 1].to_s + ',' + yval[y + 1].to_s + ',' + drawOrder.to_s)
              end
            end
          end
        end
      end

    else
      # initial link full extent
      xml.name { xml.cdata!(@layer.name) }
      xml.Style  do
        xml.ListStyle do
          xml.listItemType('checkHideChildren')
        end
      end

      xml.NetworkLink do
        # xml.visibility(1)
        if depictsYear.present?
          xml.TimeStamp do
            xml.when(depictsYear)
          end
        end
        xml.Region do
          xml.LatLonAltBox do
            xml.north(north)
            xml.south(south)
            xml.east(east)
            xml.west(west)
          end
          xml.Lod do
            xml.minLodPixels(128)
            xml.maxLodPixels(-1)
          end
        end
        xml.Link do
          xml.viewRefreshMode('onRequest')
          xml.href(this_baseurl + '?DBOX=' + west.to_s + ',' + south.to_s + ',' + east.to_s + ',' + north.to_s + ',1')
        end
      end
    end
  end
end
