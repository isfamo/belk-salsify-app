class GroupingId < ApplicationRecord

  def self.increment
    last.update_attributes({sequence: last.sequence + 1})
  end

end