class UpdateEventParentIds

  def self.run
    new.run
  end

  def run
    CMAEvent.where("parent_id is not null").each do |event|
      parent_id = Sku.find_by(product_id: event.sku_code).parent_id
      raise event unless parent_id
      next if event.parent_id == parent_id
      puts "updating #{event.sku_code} from #{event.parent_id} to #{parent_id}"
      event.update(parent_id: parent_id)
    end
  end

end
