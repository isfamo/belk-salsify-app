describe SalsifyTree do
  def create_root_node
    SalsifySqlNode.new(parent_sid: nil, sid: :root, data: {})
  end

  def populate_nodes(parent, count, random = true)
    res = []
    count.times do
      res << SalsifySqlNode.new(parent_sid: parent.sid, sid: random == true ? Faker::Lorem.characters(6) : random, data: {})
    end
    res
  end

  def prepare_sql_data
    # Categories
    SalsifySqlNode.delete_all
    CfhExecutionError.delete_all
    SalsifyCfhExecution.delete_all
    today_exec = SalsifyCfhExecution.auto_today.first_or_create
    csv = File.read('spec/lib/cfh_integration/cfh_utils/category_hierarchy.csv')
    rows = CSV.parse(csv)
    rows.shift
    rows.first(10).each do |row|
      SalsifySqlNode.find_or_create_by(sid: row[0], parent_sid: row[3], salsify_cfh_execution_id: today_exec.id) do |product|
        product.data = {
          name: row[1],
          attribute_id: row[2]
        }
      end
    end

    # Products
    SalsifySqlNode.all.each do |category|
      SalsifySqlNode.create(sid: Faker::Lorem.characters(8), parent_sid: category.sid, node_type: 'product', salsify_cfh_execution_id: today_exec.id,
      data: {
        name: Faker::Commerce.product_name
      })
    end

    # Add one more product to beauty-bath-body-bubble-baths-soaks for #on_demand_nodes test
    SalsifySqlNode.create(sid: 'product 2', parent_sid: 'beauty-bath-body-bubble-baths-soaks', node_type: 'product', salsify_cfh_execution_id: today_exec.id,
      data: { name: 'product 2 name'}
    )

    # Category mistakenly included as product
    SalsifySqlNode.create(sid: 'beauty-bath-body', parent_sid: 'beauty', node_type: "product", salsify_cfh_execution_id: today_exec.id,
      data: { name: 'bed-bath'}
    )
  end

  context 'With SQL data - ' do
    before(:all) do
      prepare_sql_data
      nodes = Array.wrap(SalsifySqlNode.new(sid: :root))
      nodes.push(*SalsifySqlNode.all)
      @tree = SalsifyTree.new(nodes)
    end

    after(:all) do
      SalsifySqlNode.delete_all
      CfhExecutionError.delete_all
      SalsifyCfhExecution.delete_all
    end

    context '::initialize' do
      it 'should create the tree from the SQL data' do
        expect(@tree).to be_kind_of(SalsifyTree)
      end
    end

    context '::to_json' do
      it 'should return the json version for the tree' do
        result = JSON.parse @tree.to_json
        expect(result["nodes"].count).to be(1)
        expect(result["nodes"][0]["nodes"].count).to be(3)
      end
    end
  end

  context '::initialize' do
    before do
      # 4 level tree
      @objects = [create_root_node]
      @objects.push *populate_nodes(@objects[0], 3)
      @objects.last(3).each do |parent|
        @objects.push *populate_nodes(parent, 3)
      end
      @objects.last(9).each do |parent|
        @objects.push *populate_nodes(parent, 5)
      end
    end

    it 'should raise an error if root is missing' do
      expect {
        @objects.shift

        tree = SalsifyTree.new(@objects)
      }.to raise_error(SalsifyTree::MissingTreeRoot)
    end

    it 'should create a tree successfully' do
      tree = SalsifyTree.new(@objects)
      expect(tree.root.children.count).to be(3)
      expect(tree.root.children[0].children.count).to be(3)
      expect(tree.root.children[0].children[0].children.count).to be(5)
    end
  end

  context '::initialize' do
    it 'should create a tree from category_hierarchy.csv' do
      csv = CustomCSV::Wrapper.new('lib/cfh_integration/cache/category_hierarchy.csv')
      nodes = []
      csv.foreach do |node|
        hash = node.to_h
        nodes << SalsifySqlNode.new(parent_sid: hash[:salsifyparent_id], sid: hash[:salsifyid], data: {
          name: hash[:salsifyname]
        })
      end
      tree = SalsifyTree.new(nodes)
      expect(tree.root.name).to eq("root")
      expect(tree.root.children.map(&:name)).to eq(["beauty", "bed-bath", "for-the-home", "handbags-accessories", "jewelry",
        "juniors", "kids-baby", "mens", "shoes", "womens"])
      expect(tree.root.count).to eq(852)
    end
  end

  context '#on_demand_nodes' do
    it 'should filter nodes by the sid' do
      prepare_sql_data
      sid_one = 'beauty-bath-body-bubble-baths-soaks'
      sid_two = 'beauty'
      cfh_exec = SalsifyCfhExecution.auto_today.first_or_create.salsify_sql_nodes
      expect(cfh_exec.on_demand_nodes(sid_one).count).to eq 3
      expect(cfh_exec.on_demand_nodes(sid_two).count).to eq 22
    end
  end

  context '#diff' do
    it 'should compare trees with root only' do
      objects = [create_root_node]
      tree1 = SalsifyTree.new(objects)

      objects = [create_root_node]
      tree2 = SalsifyTree.new(objects)

      diff = tree1.diff(tree2)
      expect(diff).to be(tree2)
    end

    it 'should compare two completely different trees' do
      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 3)
      tree1 = SalsifyTree.new(objects)

      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 3)
      tree2 = SalsifyTree.new(objects)
      diff = tree1.diff(tree2)
      expect(diff.root.children.count).to be(6)
      expect(diff.root.children.map(&:delta_status)).to eq([:removed, :removed, :removed, :added, :added, :added])
    end


    it 'should compare two completely different trees' do
      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 3)
      tree1 = SalsifyTree.new(objects)

      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 3)
      tree2 = SalsifyTree.new(objects)
      diff = tree1.diff(tree2)
      expect(diff.root.children.count).to be(6)
      expect(diff.root.children.map(&:delta_status)).to eq([:removed, :removed, :removed, :added, :added, :added])
    end

    it 'should compare two trees with one same node' do
      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 1)
      objects.push *populate_nodes(objects[0], 1, "COMMON1")
      objects.push *populate_nodes(objects[0], 1, "COMMON2")
      tree1 = SalsifyTree.new(objects)

      objects = [create_root_node]
      objects.push *populate_nodes(objects[0], 1)
      objects.push *populate_nodes(objects[0], 1, "COMMON1")
      objects.push *populate_nodes(objects[0], 1, "COMMON2")
      tree2 = SalsifyTree.new(objects)
      diff = tree1.diff(tree2)
      expect(diff.root.children.count).to be(4)
      expect(diff.root.children.map(&:delta_status)).to eq([:removed, :unchanged, :unchanged, :added])
    end
  end
end
