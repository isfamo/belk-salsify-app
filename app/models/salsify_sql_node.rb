class SalsifySqlNode < ApplicationRecord
  validates :sid, presence: true
  validates :salsify_cfh_execution_id, presence: true
  belongs_to :salsify_cfh_execution

  scope :products, -> {
    where(node_type: 'product')
  }

  scope :categories, -> {
    where(node_type: 'category')
  }

  scope :on_demand_nodes, -> (sid) {
    where("node_type = 'category' AND sid like ? OR node_type = 'product' AND parent_sid like ?", "%#{sid}%", "%#{sid}%")
  }

  scope :older_than, -> (number_of) {
    where("created_at < ? ", number_of.days.ago)
  }

  def tree_data
    data.symbolize_keys.merge({
      node_type: node_type,
      parent_sid: parent_sid
    })
  end

  def self.tree_nodes(product_ids, execution_id)
    execution = SalsifyCfhExecution.find(execution_id)
    categories = execution.salsify_sql_nodes.categories
    products = execution.salsify_sql_nodes.where(id: product_ids)
    categories + products
  end

  def self.changed_products(day, today_execution_id, yesterday_execution_id)
    init_id, subsequenet_id = execution_order(day, today_execution_id, yesterday_execution_id)
    ActiveRecord::Base.connection.execute(
      "select id from salsify_sql_nodes where salsify_cfh_execution_id = #{init_id} and node_type = 'product' and (sid || parent_sid) in
      ((select (sid || parent_sid) from salsify_sql_nodes where salsify_cfh_execution_id = #{init_id}) EXCEPT
      (select (sid || parent_sid) from salsify_sql_nodes where salsify_cfh_execution_id = #{subsequenet_id}))"
    ).pluck('id')
  end

  def self.execution_order(day, today_execution_id, yesterday_execution_id)
    if day == :today
      [ today_execution_id, yesterday_execution_id ]
    else
      [ yesterday_execution_id, today_execution_id ]
    end
  end
end
