class CreateGroupingIdsTable < ActiveRecord::Migration[5.0]
  def change
    create_table :grouping_ids do |t|
      t.integer :sequence
    end
  end
end
