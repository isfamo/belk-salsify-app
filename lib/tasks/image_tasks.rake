namespace :images do
  require_rel '../image_management/**/*.rb'
  require_rel '../concerns/**/*.rb'
  
  task send_unsent_vendor_images: :environment do
    ImageManagement::ImageTransfer.send_unsent_assets
  end

end
