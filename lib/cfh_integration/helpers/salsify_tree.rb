# Extend RubyTree classes to include a delta_status field
# https://github.com/evolve75/RubyTree/blob/master/lib/tree.rb

class Tree::TreeNode
  attr_writer :delta_status
  DEFAULT_NAME = 'Demandware Category'

  # These statuses are project-defined and make sense
  # only in the context of a delta export
  # :added, :removed, :unchanged, :updated
  def delta_status
    return :unchanged if dup_is_root?
    @delta_status
  end

  # Salsify implementation of root
  def dup_is_root?
    content[:parent_sid] == nil
  end

  # Based on the node's properties we decide
  # if it should be included in the XML or not
  def skip_from_xml?
    return true if delta_status == :unchanged
    return true if content[:parent_sid].presence == nil # Root Node or Invalid Node
    return true if name.presence == nil # Invalid node
  end

  def removed?
    delta_status == :removed
  end

  def category?
    content[:node_type] == 'category'
  end

  def product?
    content[:node_type] == 'product'
  end

  def node_type
    content[:node_type]
  end

  ####
  # This helps for tracking down the path to a node, also useful for debugging
  # as seen here: https://github.com/evolve75/RubyTree/issues/48
  def path_as_string(separator)
    get_path_array.reverse.join(separator)
  end

  def path_as_array
    get_path_array.reverse
  end

  def get_path_array(current_array_path = [])
    path_array = current_array_path + [name]
    if !parent
      return path_array
    else
      path_array=parent.get_path_array(path_array)
      return path_array
    end
  end
  ####

  # This is used to compute the JSON version of the node
  # It is consumed by the web app to display
  # the data in the graph
  def as_json(options = {})
    json_hash = {
      'text'         => dup_is_root? ? DEFAULT_NAME : content[:name],
      'description'  => content.except(:name, :node_type, :parent_sid)
    }
    json_hash['parent'] = parent.dup_is_root? ? DEFAULT_NAME : parent.content[:name] if parent
    json_hash['sid'] = name
    if !dup_is_root?
      json_hash['links'] = {
        'metadata' => "https://app.salsify.com/app/products/#{name}"
      }
      json_hash['links']['list'] = "https://app.salsify.com/app/product_lists/#{content[:list_id]}?perPage=25" if content[:list_id].present?
    end

    if has_children?
      json_hash['nodes'] = children
    end

    return json_hash
  end
end

class SalsifyTree
  attr_accessor :root, :default_delta_status, :sid

  # default_delta_status
  # :removed =>
  #   - for diff-ing two trees we need the default delta status to be :removed
  #   - the diff-ing algorith assumes all nodes were removed and marks as added/unchanged
  #   each node which is present in both the trees A and B
  #   For more details about the diff-ing algorithm see method 'diff(tree)'
  # :added =>
  #   - for generating a CFH for today but without doing any diffing
  #   - because the status will be added the node will appear in the Delta XML
  #   - this should only be used for exporting the CFH to XML for testing purposes,
  #   since it doesn't assume any real use-case scenario

  def initialize(objects, default_delta_status = :removed, sid: nil)
    if sid
      root = objects.find { |object| object.sid == sid }
    else
      root = objects.find { |object| object.sid == 'root' && object.parent_sid == nil }
    end
    @sid = sid
    raise MissingTreeRoot, "#{sid} missing node with parent" unless root
    @default_delta_status = default_delta_status
    @root = Tree::TreeNode.new(root.sid, root.tree_data)

    puts 'grouping nodes...'
    objects = objects.group_by { |x| x.parent_sid }

    puts 'creating tree...'
    start_time = Time.now
    create_tree(objects)
    puts "SalsifyTree assembled in #{(Time.now - start_time) / 60} minutes"
  end

  def to_json
    root.to_json
  end

  # Used by the web for 'On Demand Export'
  # From a tree we extract only a subset of it
  # name - the name of the node which will be the subset's root
  def subset(name)
    root.each do |node|
      if node.name == sid
        @root = node
        return self
      end
    end
    nil
  end

  # self - usually today's tree
  # tree - usually yesterday's tree

  # Each node is identified by a (name, parent, level) combination

  ### Description: ###
  # We traverse today's tree and do a straight lookup for each node in yesterday's tree
  # If the node is also present in yesterday's tree, we mark it as `unchanged`
  # If the node is missing from yesterday's tree, we mark it as added
  # There is a default status of removed which handles cases where it is not in today's tree but was in yeseterday's
  # default_delta_status ( see default_delta_status doc )

  # Output: The resulted merged tree will have
  # all nodes with a `delta_status` associated.
  # `delta_status` will have one of the following values:
  # `added`, `removed`, or `unchanged`
  def diff(tree)
    root.each_with_index do |node, index|
      next if node.is_root?
      parent = get_tree_node(tree, node.parent)
      existing = parent[node.name]
      if existing
        set_node_status(existing, :unchanged)
      else
        flattened_node = node.dup.remove_all!
        set_node_status(flattened_node, :added)
        parent << flattened_node
      end
    end
    tree
  end

  def on_demand_diff(tree)
    root.each do |node|
      next if node.is_root? || node.name == sid
      parent = tree.root.find { |_node| _node.name == node.parent.name }
      existing = parent[node.name]
      if existing
        set_node_status(existing, :unchanged)
      else
        set_node_status(node, :added)
        parent << node
      end
    end
    tree
  end

  private

  def set_node_status(node, status)
    node.delta_status = status
  end

  # this does a traversal - slow
  def find_node_in_tree(tree, searched)
    tree.root.each do |node|
      return node if node.name == searched.name && \
        node.level == searched.level && \
        node.parent.try(:name) == searched.parent.try(:name)
    end
  end

  # this goes to the node directly (if doesn't exist it was return nil)
  def get_tree_node(tree, searched)
    # the old way was find_node_in_tree which would traverse the tree
    # but the tree is a hash, should be able to check for a specific node directly
    node = tree.root
    searched.path_as_array.each do |test_node_name|
      next if test_node_name == 'root'
      if node[test_node_name]
        node = node[test_node_name]
      else
        # failed lookup, so a nil will show couldn't find
        return nil
      end
    end
    node
  end

  def create_tree(objects)
    to_be_seen = [@root]
    to_be_seen.each do |node|
      # slice array so we don't overload rubys memory
      children(objects, node).each_slice(100_000) do |sub_children|
        to_be_seen.push(*sub_children)
      end
    end
  end

  def categories
    @categories ||= SalsifySqlNode.categories.map(&:sid).uniq
  end

  def children(objects, parent)
    return [] unless objects[parent.name]

    objects[parent.name].each do |child|
      # catagories may unintentionally be included as poducts. If so, we skip them for two reasons
      # 1) we don't want 'fake products' to be included on the XML
      # 2) if a category is included in it's own list, we enter an infitite loop
      next if child.node_type == 'product' && categories.include?(child.sid)
      tree_child = Tree::TreeNode.new(child.sid, child.tree_data)
      set_node_status(tree_child, default_delta_status)
      parent << tree_child
    end
    parent.children
  end

  class MissingTreeRoot < StandardError; end

end
