class RemoveIrreleventCategories

  attr_reader :cfh_execution, :category

  def initialize(cfh_execution, category)
    @cfh_execution = cfh_execution
    @category = category
  end

  def self.run(cfh_execution, categories)
    new(cfh_execution, categories).run
  end

  def run
    cfh_execution.salsify_sql_nodes.delete(*nodes_to_delete)
  end

  def nodes_to_delete
    cfh_execution.salsify_sql_nodes.categories - nodes_to_keep.to_a
  end

  def nodes_to_keep
    Set.new(relavant_nodes).tap { |nodes| append_parent_nodes(nodes) }
  end

  def append_parent_nodes(nodes)
    nodes.map do |node|
      cfh_execution.salsify_sql_nodes.find { |sql_node| sql_node.sid == node.parent_sid }
    end.compact.each { |node| nodes.add(node) } until nodes.find { |node| node.sid == 'root' }
  end

  # fetch category and all underlying child categories
  def relavant_nodes
    cfh_execution.salsify_sql_nodes.categories.select do |node|
      category == node.sid || node.try(:parent_sid).try(:include?, category)
    end
  end

end
