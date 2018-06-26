class AddIndexToSalsifySqlNodes < ActiveRecord::Migration[5.0]
  def change
    remove_index :salsify_sql_nodes, :node_type
    add_index :salsify_sql_nodes, :salsify_cfh_execution_id, using: :btree
    add_index :salsify_sql_nodes, [ :node_type, :parent_sid, :sid ],  using: :btree
  end
end
