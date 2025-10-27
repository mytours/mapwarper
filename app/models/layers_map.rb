class LayersMap < ActiveRecord::Base
  belongs_to :layer
  belongs_to :map

  validates :layer_id, uniqueness: { scope: :map_id, message: :already_has_map }
end
