class CreateSalsifySqlNodes < ActiveRecord::Migration[5.0]
  def change
    create_table :salsify_sql_nodes do |t|
      t.string :sid
      t.json :data, default: {}
      t.string :parent_sid
      t.string :node_type, default: :category
      t.timestamps
    end

    add_index :salsify_sql_nodes, :sid, using: :btree
    add_index :salsify_sql_nodes, :parent_sid, using: :btree
    add_index :salsify_sql_nodes, :node_type, using: :btree
  end
end
