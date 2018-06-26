FactoryGirl.define do
  factory :cma_event do
    sku_code { Faker::Lorem.characters(10) } 
    vendor_upc "32677611623" 
    record_type "51"  
    event_id { Faker::Lorem.characters(6) }
    start_date DateTime.now.utc.beginning_of_day
    end_date (DateTime.now + 1.day).utc.end_of_day
    adevent { Faker::Lorem.characters(10) }
  end
end
