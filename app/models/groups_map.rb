class GroupsMap < ActiveRecord::Base
  belongs_to :group
  belongs_to :map
  validates :map_id, uniqueness: { scope: :group_id, message: 'Map has already been saved to this group' }
end
