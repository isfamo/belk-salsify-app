describe SalsifySqlNode, type: :model do

  let(:execution) { SalsifyCfhExecution.auto_today.first_or_create }
  let(:execution_two) { SalsifyCfhExecution.create }

  before :each do
    SalsifySqlNode.create!(sid: 'product_one', parent_sid: 'category_one', node_type: 'product', salsify_cfh_execution_id: execution.id)
    SalsifySqlNode.create!(sid: 'product_three', parent_sid: 'category_one', node_type: 'product', salsify_cfh_execution_id: execution.id)
    SalsifySqlNode.create!(sid: 'category_one', salsify_cfh_execution_id: execution.id)
    SalsifySqlNode.create!(sid: 'product_two', parent_sid: 'category_one', node_type: 'product', salsify_cfh_execution_id: execution_two.id)
    SalsifySqlNode.create!(sid: 'product_three', parent_sid: 'category_one', node_type: 'product', salsify_cfh_execution_id: execution_two.id)
  end

  context self do
    it 'should create a valid row - valid date' do
      row = SalsifySqlNode.new(
        sid: 'A', data: { test: 'a', test2: { test3: 'B' } }, salsify_cfh_execution_id: execution.id
      )
      expect(row.save).to eq(true)
      expect(row.data).to be_kind_of(Hash)
      expect(row.sid).to eq("A")
    end

    it '#changed_products' do
      todays_ids = SalsifySqlNode.changed_products(:today, execution.id, execution_two.id)
      yesterdays_ids = SalsifySqlNode.changed_products(:yesterday, execution.id, execution_two.id)
      expect(todays_ids).to eq [13758]
      expect(yesterdays_ids).to eq [13761]
    end

    it '#tree_nodes' do
      todays_ids = SalsifySqlNode.changed_products(:today, execution.id, execution_two.id)
      yesterdays_ids = SalsifySqlNode.changed_products(:yesterday, execution.id, execution_two.id)
      expect(SalsifySqlNode.tree_nodes(todays_ids, execution).count).to eq 2
      expect(SalsifySqlNode.tree_nodes(yesterdays_ids, execution_two).count).to eq 1
    end
  end

end
