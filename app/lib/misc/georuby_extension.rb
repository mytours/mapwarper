require 'geo_ruby/ewk'
module GeoRuby
  module SimpleFeatures
    class Polygon
      def to_json(_options = nil)
        coords = first.points.collect { |point| [point.x, point.y] }
        { type: 'Polygon',
          coordinates: coords }.to_json
      end
    end

    class Point
      def to_json(_options = nil)
        { type: 'Point',
          coordinates: [x, y] }.to_json
      end
    end

    class LineString
      def to_json(_options = nil)
        coords = points.collect { |point| [point.x, point.y] }
        { type: 'LineString',
          coordinates: coords }.to_json
      end
    end

    class GeometryCollection
      def to_json(_options = nil)
        { type: 'GeometryCollection',
          geometries: geometries }.to_json
      end
    end
  end
end
