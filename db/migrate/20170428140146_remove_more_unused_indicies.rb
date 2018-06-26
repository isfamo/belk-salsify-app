class RemoveMoreUnusedIndicies < ActiveRecord::Migration[5.0]
  def change
    remove_index :salsify_sql_nodes, :parent_sid
    remove_index :cma_events, :end_date
    remove_index :cma_events, :start_date
  end
end
