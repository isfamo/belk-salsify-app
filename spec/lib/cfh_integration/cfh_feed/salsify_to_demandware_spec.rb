describe SalsifyToDemandware do

  before :all do
    today_exec = SalsifyCfhExecution.manual_today.first_or_create

    category_metadata_data = CSV.read(open('spec/lib/cfh_integration/cfh_utils/current_category_metadata.csv'), headers: true)
    categories = category_metadata_data.map {|row| row['product_id']}.compact
    csv = CustomCSV::Wrapper.new('./spec/lib/cfh_integration/cfh_utils/category_hierarchy.csv')
    csv.foreach do |node|
      hash = node.to_h
      next unless categories.include?(hash[:salsifyid])
      SalsifySqlNode.new(parent_sid: hash[:salsifyparent_id], sid: hash[:salsifyid], salsify_cfh_execution_id: today_exec.id, data: {
        name: hash[:salsifyname]
        }).save!
    end

    category_metadata = SalsifyToDemandware::CategoryMetadata.new('salsify_client', today_exec)
    category_metadata.send(:upsert_rows, category_metadata_data)

    csv.foreach do |node|
      hash = node.to_h
      category = SalsifySqlNode.find_by(sid: hash[:salsifyid], node_type: 'category', salsify_cfh_execution_id: today_exec.id)
      next unless category
      next unless category.data['online-flag']
      SalsifySqlNode.new(node_type: "product", parent_sid: hash[:salsifyid], sid: Faker::Lorem.characters(6), salsify_cfh_execution_id: today_exec.id, data: {
        name: Faker::Commerce.product_name
        }).save!
    end
  end

  context 'categories with online-flag = false' do
    it 'persists all categories regardless of offline_flag' do
      expect(SalsifySqlNode.categories.count).to eq 11
    end

    it 'doesn\'t include skus with an offline_flag = true category' do
      expect(SalsifySqlNode.products.count).to eq 10
    end
  end

end
