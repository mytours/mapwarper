# frozen_string_literal: true

# Configure Psych (YAML) to allow RGeo classes for serialization
# This is needed for Rails 8 / Ruby 3.1+ which restricts YAML deserialization for security
# For session storage and fixtures

# Define permitted classes for YAML serialization
PERMITTED_YAML_CLASSES = [
  Symbol,
  Time,
  Date,
  BigDecimal,
  ActiveSupport::TimeWithZone,
  ActiveSupport::TimeZone,
  ActiveSupport::HashWithIndifferentAccess
].freeze

# Add RGeo classes when they're loaded
ActiveSupport.on_load(:active_record) do
  RGEO_CLASSES = [
    'RGeo::Geos::CAPIFactory',
    'RGeo::Geos::CAPIPointImpl',
    'RGeo::Geos::CAPILineStringImpl',
    'RGeo::Geos::CAPILinearRingImpl',
    'RGeo::Geos::CAPIPolygonImpl',
    'RGeo::Geos::CAPIMultiPointImpl',
    'RGeo::Geos::CAPIMultiLineStringImpl',
    'RGeo::Geos::CAPIMultiPolygonImpl',
    'RGeo::Geos::CAPIGeometryCollectionImpl',
    'RGeo::Cartesian::Factory',
    'RGeo::Cartesian::PointImpl',
    'RGeo::Cartesian::LineStringImpl',
    'RGeo::Cartesian::LinearRingImpl',
    'RGeo::Cartesian::PolygonImpl',
    'RGeo::Geographic::Factory',
    'RGeo::Geographic::ProjectedPointImpl',
    'RGeo::Geographic::SphericalPointImpl'
  ].freeze
end

module Psych
  class << self
    alias original_safe_load safe_load
    alias original_safe_dump safe_dump if respond_to?(:safe_dump)

    def safe_load(yaml, *, **kwargs)
      permitted_classes = kwargs[:permitted_classes] || []
      permitted_classes += PERMITTED_YAML_CLASSES

      # Add RGeo classes if defined
      if defined?(RGEO_CLASSES)
        RGEO_CLASSES.each do |class_name|
          permitted_classes << class_name.constantize
        rescue NameError
          # Class not loaded yet, skip
        end
      end

      kwargs[:permitted_classes] = permitted_classes.compact.uniq
      original_safe_load(yaml, *, **kwargs)
    end

    def safe_dump(obj, *, **kwargs)
      permitted_classes = kwargs[:permitted_classes] || []
      permitted_classes += PERMITTED_YAML_CLASSES

      # Add RGeo classes if defined
      if defined?(RGEO_CLASSES)
        RGEO_CLASSES.each do |class_name|
          permitted_classes << class_name.constantize
        rescue NameError
          # Class not loaded yet, skip
        end
      end

      kwargs[:permitted_classes] = permitted_classes.compact.uniq

      if respond_to?(:original_safe_dump)
        original_safe_dump(obj, *, **kwargs)
      else
        # Fallback to regular dump if safe_dump doesn't exist
        dump(obj, *)
      end
    end
  end
end
